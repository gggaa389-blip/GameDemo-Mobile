extends Control
## Start screen: play alone, host a LAN game, or join one found on the network.
## Also carries the on-device diagnostics: if the game scene cannot start, this
## screen tells us why instead of leaving a black screen.

const GAME_SCENE := "res://src/app/App.tscn"

var _status: Label
var _hosts_box: VBoxContainer
var _ip_edit: LineEdit
var _diag_label: Label
var _overlay: PanelContainer
var _overlay_text: Label
var _buttons: Array[Button] = []

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	Net.hosts_changed.connect(_refresh_hosts)
	Net.connection_error.connect(func(msg: String) -> void: _set_status("Connection failed: " + msg))
	Net.connected_ok.connect(func() -> void: _set_status("Connected! Starting game..."))
	_refresh_hosts()
	_update_diag()
	if Net.diag_requested:
		Net.diag_requested = false
		_status.text = "لم تبدأ اللعبة على هذا الجهاز — أرسل صورة لهذه الشاشة."
		_toggle_overlay()
	_handle_cmdline()

# ------------------------------------------------------------ diagnostics ----

func _cs_status() -> String:
	var script := load("res://src/app/App.cs")
	if script == null:
		return "C#: SCRIPT NOT FOUND"
	if script is Script and not (script as Script).can_instantiate():
		return "C#: NOT AVAILABLE (.NET failed to load)"
	return "C#: OK"

func _device_info() -> String:
	var lines: PackedStringArray = []
	lines.append("Godot: " + str(Engine.get_version_info().get("string", "?")))
	lines.append("OS: %s %s (%s)" % [OS.get_name(), OS.get_version(), OS.get_processor_name()])
	lines.append("Device: %s / %s" % [OS.get_model_name(), OS.get_unique_id().substr(0, 8)])
	lines.append("Renderer: %s" % RenderingServer.get_video_adapter_name())
	lines.append("Driver: %s %s" % [RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_api_version()])
	lines.append("Rendering method: %s" % ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile", "?"))
	lines.append("CPU cores: %d  |  screen: %s" % [OS.get_processor_count(), str(get_viewport_rect().size)])
	lines.append("App scene loadable: %s" % str(ResourceLoader.exists(GAME_SCENE)))
	lines.append(_cs_status())
	return "\n".join(lines)

func _log_tail(max_lines := 140) -> String:
	var path := "user://logs/godot.log"
	if not FileAccess.file_exists(path):
		return "(no log file at " + path + ")"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "(cannot open log file)"
	var lines: PackedStringArray = []
	while not f.eof_reached() and lines.size() < 6000:
		lines.append(f.get_line())
	var start: int = max(0, lines.size() - max_lines)
	var tail := PackedStringArray()
	for i in range(start, lines.size()):
		tail.append(lines[i])
	return "\n".join(tail)

func _update_diag() -> void:
	if _diag_label != null:
		_diag_label.text = "%s   ·   %s" % [_cs_status(), RenderingServer.get_video_adapter_name()]

func _toggle_overlay() -> void:
	if _overlay == null:
		return
	if _overlay.visible:
		_overlay.hide()
		return
	_overlay_text.text = _device_info() + "\n\n----- log tail -----\n" + _log_tail()
	_overlay.show()

# ------------------------------------------------------------------ build ----

func _handle_cmdline() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--solo":
			_start_solo()
			return
		if arg == "--host":
			_start_host()
			return
		if arg.begins_with("--join="):
			_start_join(arg.substr(7))
			return

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)

	var title := Label.new()
	title.text = "GAMEDEMO  ·  LAN"
	title.add_theme_font_size_override("font_size", 42)
	left.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Play alone, or play with a friend over a phone hotspot — no internet needed."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	left.add_child(subtitle)

	left.add_child(_make_button("PLAY ALONE", _start_solo, Color(0.2, 0.55, 0.35)))
	left.add_child(_make_button("HOST GAME  (this phone opens the hotspot)", _start_host, Color(0.2, 0.45, 0.75)))

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 12)
	left.add_child(join_row)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "192.168.43.1"
	_ip_edit.text = "192.168.43.1"
	_ip_edit.custom_minimum_size = Vector2(300, 76)
	_ip_edit.add_theme_font_size_override("font_size", 24)
	join_row.add_child(_ip_edit)
	var join_btn := _make_button("JOIN", func() -> void: _start_join(_ip_edit.text.strip_edges()), Color(0.65, 0.45, 0.15))
	join_btn.custom_minimum_size = Vector2(200, 76)
	join_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	join_row.add_child(join_btn)

	_status = Label.new()
	_status.text = "Ready."
	_status.add_theme_font_size_override("font_size", 20)
	_status.add_theme_color_override("font_color", Color(0.6, 0.85, 0.75))
	left.add_child(_status)

	var diag_row := HBoxContainer.new()
	diag_row.add_theme_constant_override("separation", 12)
	left.add_child(diag_row)
	var log_btn := _make_button("DIAGNOSTICS / السجل", _toggle_overlay, Color(0.35, 0.3, 0.5))
	log_btn.custom_minimum_size = Vector2(260, 60)
	log_btn.add_theme_font_size_override("font_size", 20)
	diag_row.add_child(log_btn)
	_diag_label = Label.new()
	_diag_label.add_theme_font_size_override("font_size", 16)
	_diag_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.8))
	_diag_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	diag_row.add_child(_diag_label)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	row.add_child(right)

	var found := Label.new()
	found.text = "GAMES FOUND ON THIS NETWORK"
	found.add_theme_font_size_override("font_size", 22)
	found.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
	right.add_child(found)

	_hosts_box = VBoxContainer.new()
	_hosts_box.add_theme_constant_override("separation", 10)
	right.add_child(_hosts_box)

	var help := Label.new()
	help.text = "How to play with a friend:\n1. Phone A: Settings > Hotspot > turn it on.\n2. Phone B: connect to phone A's hotspot.\n3. Phone A: HOST GAME.  Phone B: JOIN (its name appears here automatically)."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 17)
	help.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	right.add_child(help)

	_build_overlay()

func _build_overlay() -> void:
	_overlay = PanelContainer.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.05, 0.97)
	style.border_color = Color(0.3, 0.5, 0.8)
	style.set_border_width_all(2)
	_overlay.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	_overlay.add_child(vbox)
	var top := HBoxContainer.new()
	vbox.add_child(top)
	var close := Button.new()
	close.text = "✕  CLOSE"
	close.custom_minimum_size = Vector2(160, 54)
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(_toggle_overlay)
	top.add_child(close)
	var hint := Label.new()
	hint.text = "  Send a screenshot of this screen if the game does not start."
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	top.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_overlay_text = Label.new()
	_overlay_text.add_theme_font_size_override("font_size", 13)
	_overlay_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_overlay_text.text = ""
	scroll.add_child(_overlay_text)

func _make_button(text: String, cb: Callable, tint: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 84)
	button.add_theme_font_size_override("font_size", 26)
	var normal := StyleBoxFlat.new()
	normal.bg_color = tint
	normal.set_corner_radius_all(14)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = tint.lightened(0.15)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = tint.darkened(0.2)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.pressed.connect(cb)
	_buttons.append(button)
	return button

func _refresh_hosts() -> void:
	if _hosts_box == null:
		return
	for child in _hosts_box.get_children():
		child.queue_free()
	if Net.hosts.is_empty():
		var empty := Label.new()
		empty.text = "Searching..." if Net.mode != Net.Mode.HOST else "You are hosting."
		empty.add_theme_font_size_override("font_size", 19)
		empty.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
		_hosts_box.add_child(empty)
		return
	for ip in Net.hosts.keys():
		var info: Dictionary = Net.hosts[ip]
		var button := _make_button("%s   (%s)" % [info.name, ip], _on_host_pressed.bind(ip), Color(0.25, 0.35, 0.6))
		button.custom_minimum_size = Vector2(0, 70)
		_hosts_box.add_child(button)

func _on_host_pressed(ip: String) -> void:
	_start_join(ip)

func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text

# --------------------------------------------------------------- starting ----

## Loads the game scene *before* leaving this screen, so a broken scene shows an
## error here instead of a black screen.
func _enter_game() -> void:
	var packed: PackedScene = load(GAME_SCENE) as PackedScene
	if packed == null:
		_fail("لا يمكن تحميل مشهد اللعبة (App.tscn) — الملف تالف أو مفقود في هذه النسخة.")
		return
	var probe: Node = packed.instantiate()
	if probe == null:
		_fail("فشل إنشاء مشهد اللعبة. غالبًا مشكلة في تحميل أكواد C#/.NET على هذا الجهاز.")
		return
	probe.free()
	Net.arm_watchdog()
	get_tree().change_scene_to_file(GAME_SCENE)

func _fail(message: String) -> void:
	_set_status("ERROR: " + message)
	if _overlay != null:
		_overlay_text.text = "! " + message + "\n\n" + _device_info() + "\n\n----- log tail -----\n" + _log_tail()
		_overlay.show()

func _start_solo() -> void:
	Net.close()
	_enter_game()

func _start_host() -> void:
	var err := Net.host_game()
	if err != "":
		_set_status("Could not host: " + err)
		return
	_set_status("Hosting on port %d — your friend joins the same hotspot." % Net.PORT)
	_enter_game()

func _start_join(ip: String) -> void:
	if ip == "":
		_set_status("Type the host's IP first (usually 192.168.43.1).")
		return
	var err := Net.join_game(ip)
	if err != "":
		_set_status("Could not join: " + err)
		return
	_set_status("Connecting to %s ..." % ip)
	_enter_game()
