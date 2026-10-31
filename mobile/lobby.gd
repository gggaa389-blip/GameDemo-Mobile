extends Control
## Start screen: play alone, host a LAN game, or join one found on the network.

const GAME_SCENE := "res://src/app/App.tscn"

var _status: Label
var _hosts_box: VBoxContainer
var _ip_edit: LineEdit
var _buttons: Array[Button] = []

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	Net.hosts_changed.connect(_refresh_hosts)
	Net.connection_error.connect(func(msg: String) -> void: _set_status("Connection failed: " + msg))
	Net.connected_ok.connect(func() -> void: _set_status("Connected! Starting game..."))
	_refresh_hosts()
	_handle_cmdline()

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
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 48)
	margin.add_child(row)

	# --- left: actions
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 18)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)

	var title := Label.new()
	title.text = "GAMEDEMO  ·  LAN"
	title.add_theme_font_size_override("font_size", 46)
	left.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Play alone, or play with a friend over a phone hotspot — no internet needed."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 22)
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
	_ip_edit.custom_minimum_size = Vector2(320, 84)
	_ip_edit.add_theme_font_size_override("font_size", 26)
	join_row.add_child(_ip_edit)
	var join_btn := _make_button("JOIN", func() -> void: _start_join(_ip_edit.text.strip_edges()), Color(0.65, 0.45, 0.15))
	join_btn.custom_minimum_size = Vector2(220, 84)
	join_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	join_row.add_child(join_btn)

	_status = Label.new()
	_status.text = "Ready."
	_status.add_theme_font_size_override("font_size", 20)
	_status.add_theme_color_override("font_color", Color(0.6, 0.85, 0.75))
	left.add_child(_status)

	# --- right: discovered games
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 14)
	row.add_child(right)

	var found := Label.new()
	found.text = "GAMES FOUND ON THIS NETWORK"
	found.add_theme_font_size_override("font_size", 24)
	found.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
	right.add_child(found)

	_hosts_box = VBoxContainer.new()
	_hosts_box.add_theme_constant_override("separation", 12)
	right.add_child(_hosts_box)

	var help := Label.new()
	help.text = "How to play with a friend:\n1. Phone A: Settings > Hotspot > turn it on.\n2. Phone B: connect to phone A's hotspot.\n3. Phone A: HOST GAME.  Phone B: JOIN (its name appears here automatically)."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 18)
	help.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	right.add_child(help)

func _make_button(text: String, cb: Callable, tint: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 96)
	button.add_theme_font_size_override("font_size", 28)
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
		empty.add_theme_font_size_override("font_size", 20)
		empty.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
		_hosts_box.add_child(empty)
		return
	for ip in Net.hosts.keys():
		var info: Dictionary = Net.hosts[ip]
		var button := _make_button("%s   (%s)" % [info.name, ip], _on_host_pressed.bind(ip), Color(0.25, 0.35, 0.6))
		button.custom_minimum_size = Vector2(0, 76)
		_hosts_box.add_child(button)

func _on_host_pressed(ip: String) -> void:
	_start_join(ip)

func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text

func _start_solo() -> void:
	Net.close()
	get_tree().change_scene_to_file(GAME_SCENE)

func _start_host() -> void:
	var err := Net.host_game()
	if err != "":
		_set_status("Could not host: " + err)
		return
	_set_status("Hosting on port %d — your friend joins the same hotspot." % Net.PORT)
	get_tree().change_scene_to_file(GAME_SCENE)

func _start_join(ip: String) -> void:
	if ip == "":
		_set_status("Type the host's IP first (usually 192.168.43.1).")
		return
	var err := Net.join_game(ip)
	if err != "":
		_set_status("Could not join: " + err)
		return
	_set_status("Connecting to %s ..." % ip)
	get_tree().change_scene_to_file(GAME_SCENE)
