extends Node
## Replicates the two players between the two phones.
##
## Each phone fully owns its own character (input -> physics -> camera), so the
## local player never waits for the network: zero input lag. The other player is
## a "puppet" whose transform is streamed 30 times per second and rendered
## ~90 ms in the past, interpolated between the two surrounding snapshots. That
## is what makes it look smooth instead of stuttering, even on a phone hotspot
## where packets arrive in bursts.

const SEND_RATE := 30.0
const RENDER_DELAY := 0.09
const MAX_BUFFER := 32
const HELLO_INTERVAL := 0.5

var local_player: Node3D
var puppet: Node3D
var remote_in_game := false

var _buffer: Array = []
var packets_received := 0
var _accum := 0.0
var _hello_accum := 0.0
var _spawned := false
var _time := 0.0

# ------------------------------------------------------------ pure logic ----

## Interpolates the remote player between the two snapshots that surround
## `render_time`. Exposed as a static helper so it can be unit tested.
static func sample(buffer: Array, render_time: float) -> Variant:
	if buffer.is_empty():
		return null
	if buffer.size() == 1:
		return buffer[0]
	if render_time <= buffer[0].t:
		return buffer[0]
	var last: Dictionary = buffer[buffer.size() - 1]
	if render_time >= last.t:
		return last
	for i in range(1, buffer.size()):
		var b: Dictionary = buffer[i]
		if b.t >= render_time:
			var a: Dictionary = buffer[i - 1]
			var span: float = maxf(0.0001, b.t - a.t)
			var f: float = (render_time - a.t) / span
			return {
				"t": render_time,
				"pos": (a.pos as Vector3).lerp(b.pos, f),
				"yaw": lerp_angle(a.yaw, b.yaw, f),
			}
	return last

# ---------------------------------------------------------------- setup ----

var _ready_done := false

func _ready() -> void:
	set_process(true)
	set_physics_process(true)

## NetSync may be created before the LAN mode is chosen (the lobby runs first),
## so we simply wait until there is a peer and a local player to replicate.
func _try_init() -> bool:
	if _ready_done:
		return true
	if not Net.is_multiplayer():
		return false
	var scene := get_tree().current_scene
	if scene == null:
		scene = get_tree().get_first_node_in_group("game_scene")
	local_player = scene.get_node_or_null("PauseContainer/Player") if scene else null
	if local_player == null:
		return false
	Net.host_left.connect(_on_host_left)
	_ready_done = true
	_time = Time.get_ticks_msec() / 1000.0
	return true

## The peer we replicate with. The server is always peer 1; on the host side we
## ask the multiplayer API instead of assuming an id, so we never send to a peer
## that is not connected yet.
func _other_peer() -> int:
	if Net.mode == Net.Mode.CLIENT:
		return 1
	var peers := multiplayer.get_peers()
	return peers[0] if peers.size() > 0 else 0

# --------------------------------------------------------- handshake ----

@rpc("any_peer", "call_remote", "reliable")
func _hello() -> void:
	remote_in_game = true
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0:
		rpc_id(sender, "_hello_ack")
	_ensure_puppet()

@rpc("any_peer", "call_remote", "reliable")
func _hello_ack() -> void:
	remote_in_game = true
	_ensure_puppet()

func _ensure_puppet() -> void:
	if _spawned or local_player == null:
		return
	var scene_file := load("res://src/player/Player.tscn")
	if scene_file == null:
		return
	var container := local_player.get_parent()
	puppet = scene_file.instantiate()
	puppet.name = "RemotePlayer"
	container.add_child(puppet)
	# The puppet must never simulate itself: no physics, no coin pickups.
	puppet.set_physics_process(false)
	puppet.set_process(false)
	puppet.collision_layer = 0
	puppet.collision_mask = 1
	puppet.global_transform = local_player.global_transform
	_spawned = true

# ------------------------------------------------------------ transport ----

func _physics_process(delta: float) -> void:
	if not _try_init():
		return
	_time = Time.get_ticks_msec() / 1000.0
	if not remote_in_game:
		_hello_accum += delta
		if _hello_accum >= HELLO_INTERVAL:
			_hello_accum = 0.0
			var target := _other_peer()
			if target != 0:
				rpc_id(target, "_hello")
		return
	_accum += delta
	var step := 1.0 / SEND_RATE
	while _accum >= step:
		_accum -= step
		_send_state()

func _send_state() -> void:
	if local_player == null:
		return
	var target := _other_peer()
	if target == 0:
		return
	var t := local_player.global_transform
	var velocity: Variant = local_player.get("velocity")
	rpc_id(
		target, "_receive_state", t.origin, t.basis.get_euler().y,
		velocity if velocity is Vector3 else Vector3.ZERO
	)

@rpc("any_peer", "unreliable_ordered", "call_remote")
func _receive_state(pos: Vector3, yaw: float, velocity: Vector3) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	packets_received += 1
	_buffer.append({"t": now, "pos": pos, "yaw": yaw, "vel": velocity})
	while _buffer.size() > MAX_BUFFER:
		_buffer.pop_front()
	remote_in_game = true
	_ensure_puppet()

func _process(_delta: float) -> void:
	if not _ready_done or puppet == null or _buffer.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var state: Variant = sample(_buffer, now - RENDER_DELAY)
	if state == null:
		return
	var origin: Vector3 = (state.pos as Vector3)
	var basis := Basis(Vector3.UP, state.yaw)
	puppet.global_transform = Transform3D(basis, origin)
	if state.has("vel"):
		puppet.set("velocity", state.vel)

func _on_host_left() -> void:
	remote_in_game = false
	_buffer.clear()
	if is_instance_valid(puppet):
		puppet.queue_free()
	_spawned = false
