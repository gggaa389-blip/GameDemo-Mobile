extends Node
## LAN transport for GameDemo (offline, phone hotspot friendly).
##
## * Host: ENet server on PORT + UDP broadcast advertisement every second.
## * Join: listens for advertisements (auto discovery) or takes a manual IP.
## * No internet, no relay, no accounts: everything is on the local network.

const PORT := 45871
const DISCOVERY_PORT := 45872
const MAGIC := "GDM1"
const MAX_CLIENTS := 1  # 2 players total (host + 1)

enum Mode { SOLO, HOST, CLIENT }

var mode: int = Mode.SOLO
var hosts: Dictionary = {}        # ip -> {name, time}
var last_error: String = ""
var peer_connected_flag := false

signal hosts_changed
signal connected_ok
signal connection_error(message: String)
signal host_left

var _udp_send: PacketPeerUDP
var _udp_recv: PacketPeerUDP
var _advertise_accum := 0.0
var _local_name := ""

func _ready() -> void:
	set_process(true)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_local_name = "GameDemo-" + str(randi() % 900 + 100)
	_handle_cmdline()

func _handle_cmdline() -> void:
	# The autoload is created before the first scene, so hosting / joining from
	# the command line is ready before any game node is loaded. This is what the
	# automated LAN test uses (and it also allows `--host` shortcuts).
	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			host_game()
			return
		if arg.begins_with("--join="):
			join_game(arg.substr(7))
			return

func is_multiplayer() -> bool:
	return mode != Mode.SOLO

# ------------------------------------------------------------------ host ----

func host_game() -> String:
	close()
	mode = Mode.HOST
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		last_error = "could not open port %d (error %d)" % [PORT, err]
		mode = Mode.SOLO
		return last_error
	multiplayer.multiplayer_peer = enet
	_start_advertising()
	return ""

func _start_advertising() -> void:
	_udp_send = PacketPeerUDP.new()
	_udp_send.set_broadcast_enabled(true)
	var payload := "%s|%s|%d" % [MAGIC, _local_name, PORT]
	_udp_send.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_udp_send.put_packet(payload.to_utf8_buffer())
	_advertise_accum = 0.0

func _start_listening() -> void:
	if _udp_recv != null:
		return
	_udp_recv = PacketPeerUDP.new()
	var err := _udp_recv.bind(DISCOVERY_PORT, "0.0.0.0")
	if err != OK:
		# Port busy (e.g. we are the host) - not fatal, manual IP still works.
		_udp_recv = null
		return

# ------------------------------------------------------------------ join ----

func join_game(ip: String) -> String:
	close()
	mode = Mode.CLIENT
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_client(ip, PORT)
	if err != OK:
		last_error = "could not reach %s (error %d)" % [ip, err]
		mode = Mode.SOLO
		return last_error
	multiplayer.multiplayer_peer = enet
	_start_listening()
	return ""

func close() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_udp_send = null
	peer_connected_flag = false
	mode = Mode.SOLO

func _process(delta: float) -> void:
	if mode == Mode.HOST and _udp_send != null:
		_advertise_accum += delta
		if _advertise_accum >= 1.0:
			_advertise_accum = 0.0
			var payload := "%s|%s|%d" % [MAGIC, _local_name, PORT]
			_udp_send.set_dest_address("255.255.255.255", DISCOVERY_PORT)
			_udp_send.put_packet(payload.to_utf8_buffer())
	if _udp_recv != null:
		var now := Time.get_ticks_msec() / 1000.0
		var changed := false
		while _udp_recv.get_available_packet_count() > 0:
			var text := _udp_recv.get_packet().get_string_from_utf8()
			var ip := _udp_recv.get_packet_ip()
			var parts := text.split("|")
			if parts.size() >= 3 and parts[0] == MAGIC:
				hosts[ip] = {"name": parts[1], "time": now}
				changed = true
		for ip in hosts.keys():
			if now - hosts[ip].time > 3.5:
				hosts.erase(ip)
				changed = true
		if changed:
			hosts_changed.emit()

# --------------------------------------------------------------- signals ----

func _on_peer_connected(_id: int) -> void:
	peer_connected_flag = true

func _on_peer_disconnected(_id: int) -> void:
	peer_connected_flag = false
	host_left.emit()

func _on_connected_to_server() -> void:
	peer_connected_flag = true
	connected_ok.emit()

func _on_connection_failed() -> void:
	last_error = "connection failed"
	peer_connected_flag = false
	connection_error.emit(last_error)

func _on_server_disconnected() -> void:
	peer_connected_flag = false
	host_left.emit()

func my_ip_hint() -> String:
	return "192.168.43.1"
