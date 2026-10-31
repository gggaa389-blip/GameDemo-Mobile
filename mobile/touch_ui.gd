extends Control
## Mobile touch layer for GameDemo.
##
## Left half  : analog stick  -> move_left / move_right / move_up / move_down
## Right half : drag          -> synthetic InputEventMouseMotion (rotates the
##                              player camera through the game's normal input path)
## Right side : action buttons -> jump / attack / swap_weapons / pause
## Anywhere   : taps are forwarded to the GUI as synthetic mouse clicks so all
##              the existing menus keep working with touch.
##
## The layer never touches the C# game code: it only writes to the InputMap and
## to the input event queue, exactly like a keyboard / gamepad / mouse would.

const DEAD_ZONE := 0.16
const CAM_DRAG_SCALE := 1.0

var _joy_index := -1
var _joy_center := Vector2.ZERO
var _joy_radius := 120.0
var _knob := Vector2.ZERO
var _joy_vector := Vector2.ZERO

var _buttons: Array = []
const _TAP_SLOP := 14.0
const _TAP_TIME_MS := 400

var _cam_index := -1
var _cam_last := Vector2.ZERO
var _cam_start := Vector2.ZERO
var _cam_moved := false
var _cam_press_time := 0
var _ui_index := -1

var _holding := {}  # action name -> true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_layout()
	get_viewport().size_changed.connect(_layout)
	set_process(true)
	set_process_input(true)
	set_process_unhandled_input(false)

# ---------------------------------------------------------------- layout ----

func _layout() -> void:
	var size := get_viewport_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var short := minf(size.x, size.y)
	_joy_radius = short * 0.17
	_joy_center = Vector2(size.x * 0.16, size.y * 0.73)
	_buttons = [
		{
			"name": "JUMP", "action": "jump",
			"center": Vector2(size.x * 0.855, size.y * 0.76),
			"radius": short * 0.115, "index": -1,
		},
		{
			"name": "HIT", "action": "attack",
			"center": Vector2(size.x * 0.695, size.y * 0.86),
			"radius": short * 0.09, "index": -1,
		},
		{
			"name": "SWAP", "action": "swap_weapons",
			"center": Vector2(size.x * 0.905, size.y * 0.545),
			"radius": short * 0.075, "index": -1,
		},
		{
			"name": "II", "action": "__pause",
			"center": Vector2(size.x * 0.945, size.y * 0.10),
			"radius": short * 0.058, "index": -1,
		},
	]
	queue_redraw()

func _in_game() -> bool:
	return get_tree().get_first_node_in_group("game_scene") != null

# ---------------------------------------------------------------- input ----

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_press(event.index, event.position)
		else:
			_on_release(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_on_drag(event.index, event.position, event.relative)
		get_viewport().set_input_as_handled()

func _on_press(index: int, pos: Vector2) -> void:
	if _in_game():
		if pos.distance_to(_joy_center) <= _joy_radius * 1.7:
			_joy_index = index
			_update_stick(pos)
			return
		for button in _buttons:
			if pos.distance_to(button.center) <= button.radius * 1.25:
				button.index = index
				_press_action(button.action)
				return
		var size := get_viewport_rect().size
		if pos.x > size.x * 0.42 and pos.y < size.y * 0.72:
			_cam_index = index
			_cam_last = pos
			_cam_start = pos
			_cam_moved = false
			_cam_press_time = Time.get_ticks_msec()
			queue_redraw()
			return
	# Everything else is a UI tap -> forward to the GUI as a mouse click.
	_ui_index = index
	_send_mouse_button(pos, true)

func _on_drag(index: int, pos: Vector2, relative: Vector2) -> void:
	if index == _joy_index:
		_update_stick(pos)
		return
	if index == _cam_index:
		if not _cam_moved and pos.distance_to(_cam_start) > _TAP_SLOP:
			_cam_moved = true
		# Drive the exact same code path a mouse uses.
		var motion := InputEventMouseMotion.new()
		motion.position = pos
		motion.global_position = pos
		motion.relative = Vector2(relative.x, relative.y) * CAM_DRAG_SCALE
		motion.device = 0
		Input.parse_input_event(motion)
		_cam_last = pos
		queue_redraw()
		return
	if index == _ui_index:
		var motion := InputEventMouseMotion.new()
		motion.position = pos
		motion.global_position = pos
		Input.parse_input_event(motion)

func _on_release(index: int) -> void:
	if index == _joy_index:
		_joy_index = -1
		_joy_vector = Vector2.ZERO
		_knob = Vector2.ZERO
		_release_move()
		queue_redraw()
		return
	for button in _buttons:
		if button.index == index:
			button.index = -1
			_release_action(button.action)
			return
	if index == _cam_index:
		# A short press without dragging is a tap on the UI underneath
		# (pause / win / death menus), so forward it as a click.
		if not _cam_moved and Time.get_ticks_msec() - _cam_press_time < _TAP_TIME_MS:
			_send_mouse_button(_cam_start, true)
			_send_mouse_button(_cam_start, false)
		_cam_index = -1
		queue_redraw()
		return
	if index == _ui_index:
		_ui_index = -1
		_send_mouse_button(get_viewport().get_mouse_position(), false)

func _send_mouse_button(pos: Vector2, pressed: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	Input.parse_input_event(motion)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = pressed
	click.position = pos
	click.global_position = pos
	click.device = 0
	Input.parse_input_event(click)

# -------------------------------------------------------------- actions ----

func _update_stick(pos: Vector2) -> void:
	var v := (pos - _joy_center) / _joy_radius
	if v.length() > 1.0:
		v = v.normalized()
	_joy_vector = v
	_knob = v * _joy_radius
	if absf(v.x) < DEAD_ZONE:
		_release("move_left")
		_release("move_right")
	elif v.x > 0.0:
		_press("move_right", (v.x - DEAD_ZONE) / (1.0 - DEAD_ZONE))
		_release("move_left")
	else:
		_press("move_left", (-v.x - DEAD_ZONE) / (1.0 - DEAD_ZONE))
		_release("move_right")
	if absf(v.y) < DEAD_ZONE:
		_release("move_up")
		_release("move_down")
	elif v.y > 0.0:
		_press("move_down", (v.y - DEAD_ZONE) / (1.0 - DEAD_ZONE))
		_release("move_up")
	else:
		_press("move_up", (-v.y - DEAD_ZONE) / (1.0 - DEAD_ZONE))
		_release("move_down")
	queue_redraw()

func _release_move() -> void:
	_release("move_left")
	_release("move_right")
	_release("move_up")
	_release("move_down")

func _press_action(action: String) -> void:
	if action == "__pause":
		# The game polls the built-in ui_cancel action for the pause button.
		_press("ui_cancel", 1.0)
		call_deferred("_release", "ui_cancel")
		return
	_press(action, 1.0)

func _release_action(action: String) -> void:
	if action == "__pause":
		_release("ui_cancel")
		return
	_release(action)

func _press(action: String, strength: float) -> void:
	if not InputMap.has_action(action):
		return
	_holding[action] = true
	Input.action_press(action, strength)

func _release(action: String) -> void:
	if _holding.get(action, false) or Input.is_action_pressed(action):
		_holding.erase(action)
		Input.action_release(action)

func release_all() -> void:
	_release_move()
	for button in _buttons:
		button.index = -1
		_release_action(button.action)
	_release("jump")
	_release("attack")
	_release("aim")
	_release("swap_weapons")
	_joy_index = -1
	_cam_index = -1
	_ui_index = -1
	_knob = Vector2.ZERO
	_joy_vector = Vector2.ZERO
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT \
	or what == NOTIFICATION_APPLICATION_PAUSED \
	or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		release_all()

# ----------------------------------------------------------------- draw ----

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not _in_game():
		return
	var font := ThemeDB.fallback_font
	if Net.is_multiplayer():
		var status := "LAN: connected" if Net.peer_connected_flag else "LAN: waiting for the other phone..."
		draw_string(
			font, Vector2(26, 46), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
			Color(0.55, 0.95, 0.7) if Net.peer_connected_flag else Color(0.95, 0.8, 0.4)
		)
	var line_col := Color(1, 1, 1, 0.28)
	var fill_col := Color(1, 1, 1, 0.10)
	# Analog stick
	draw_circle(_joy_center, _joy_radius, Color(1, 1, 1, 0.07))
	draw_arc(_joy_center, _joy_radius, 0, TAU, 64, line_col, 3.0, true)
	draw_arc(_joy_center, _joy_radius * 0.42, 0, TAU, 48, Color(1, 1, 1, 0.16), 2.0, true)
	draw_circle(_joy_center + _knob, _joy_radius * 0.36, Color(1, 1, 1, 0.30))
	draw_arc(_joy_center + _knob, _joy_radius * 0.36, 0, TAU, 48, Color(1, 1, 1, 0.6), 2.0, true)
	# Action buttons
	for button in _buttons:
		var pressed: bool = button.index >= 0
		var col := Color(0.35, 0.85, 1.0, 0.35) if pressed else fill_col
		draw_circle(button.center, button.radius, col)
		draw_arc(button.center, button.radius, 0, TAU, 64, line_col, 3.0, true)
		var text: String = button.name
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		draw_string(
			font, button.center - text_size * 0.5 + Vector2(0, text_size.y * 0.36),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.85)
		)
