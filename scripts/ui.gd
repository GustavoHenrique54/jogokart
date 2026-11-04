extends CanvasLayer
## Menu de conexão + HUD, montados por código.

signal join_requested(address: String, player_name: String)
signal host_requested(player_name: String)
signal practice_requested(player_name: String)
signal leave_requested

const SETTINGS_PATH := "user://settings.cfg"

var _menu: PanelContainer
var _name_edit: LineEdit
var _addr_edit: LineEdit
var _join_btn: Button
var _host_btn: Button
var _practice_btn: Button
var _resume_btn: Button
var _leave_btn: Button
var _status: Label
var _session_box: VBoxContainer
var _lobby_box: VBoxContainer

var _hud: Control
var _info: Label
var _speed: Label
var _drift: Label
var _hint: Label


func _ready() -> void:
	_build_menu()
	_build_hud()
	_load_settings()
	Net.status_changed.connect(set_status)
	show_menu("")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_menu") and Net.in_session:
		if _menu.visible:
			_hide_menu()
		else:
			_show_pause()
		get_viewport().set_input_as_handled()


func set_status(text: String) -> void:
	_status.text = text


func show_menu(reason: String) -> void:
	_menu.visible = true
	_lobby_box.visible = true
	_session_box.visible = false
	_hud.visible = false
	if reason != "":
		set_status(reason)
	_set_kart_controls(false)


func show_hud() -> void:
	_hide_menu()


func _show_pause() -> void:
	_menu.visible = true
	_lobby_box.visible = false
	_session_box.visible = true
	_set_kart_controls(false)
	_resume_btn.grab_focus()


func _hide_menu() -> void:
	_menu.visible = false
	_hud.visible = true
	_set_kart_controls(true)


func _set_kart_controls(enabled: bool) -> void:
	for k in get_tree().get_nodes_in_group("local_kart"):
		k.controls_enabled = enabled


func _process(_delta: float) -> void:
	if not _hud.visible:
		return
	# Garante que um kart recém-spawnado respeite o estado do menu.
	var kart := get_tree().get_first_node_in_group("local_kart") as Kart
	var role := "Treino offline"
	var mp := multiplayer.multiplayer_peer
	if mp and not (mp is OfflineMultiplayerPeer):
		role = "Host" if multiplayer.is_server() else "Cliente"
	var players := get_tree().get_nodes_in_group("karts").size()
	var ping := "" if Net.ping_ms < 0 else " · ping %d ms" % Net.ping_ms
	_info.text = "%s · %d no mapa%s · %d FPS" % [role, players, ping, Engine.get_frames_per_second()]
	if kart:
		kart.controls_enabled = not _menu.visible
		_speed.text = "%d km/h" % roundi(kart.get_speed_kmh())
		if kart.is_boosting():
			_drift.text = "TURBO!"
			_drift.modulate = Color(1.0, 0.6, 0.15)
		elif kart.drifting:
			var names := ["DRIFT", "MINI-TURBO", "SUPER TURBO", "ULTRA TURBO"]
			_drift.text = names[clampi(kart.drift_stage, 0, 3)]
			_drift.modulate = Kart.DRIFT_COLORS[clampi(kart.drift_stage, 0, 3)]
		else:
			_drift.text = ""


# ----------------------------------------------------------------- construção

func _build_menu() -> void:
	_menu = PanelContainer.new()
	_menu.set_anchors_preset(Control.PRESET_CENTER)
	_menu.custom_minimum_size = Vector2(460, 0)
	_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.13, 0.92)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(24)
	_menu.add_theme_stylebox_override("panel", sb)
	add_child(_menu)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	_menu.add_child(root)

	var title := Label.new()
	title.text = "JOGOKART"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	root.add_child(title)
	var sub := Label.new()
	sub.text = "protótipo de game feel · v0.1"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1, 1, 1, 0.6)
	root.add_child(sub)

	_lobby_box = VBoxContainer.new()
	_lobby_box.add_theme_constant_override("separation", 8)
	root.add_child(_lobby_box)

	_lobby_box.add_child(_label("Seu nome"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Piloto"
	_name_edit.max_length = 16
	_lobby_box.add_child(_name_edit)

	_lobby_box.add_child(_label("Servidor (link do túnel do host)"))
	_addr_edit = LineEdit.new()
	_addr_edit.placeholder_text = "wss://xxxx.trycloudflare.com  ou  localhost"
	_lobby_box.add_child(_addr_edit)

	_join_btn = _button("Entrar no servidor", _on_join)
	_lobby_box.add_child(_join_btn)
	_host_btn = _button("Hospedar partida (porta %d)" % Net.DEFAULT_PORT, _on_host)
	_host_btn.visible = not Net.is_web() # navegador não consegue ser servidor
	_lobby_box.add_child(_host_btn)
	_practice_btn = _button("Treinar sozinho", _on_practice)
	_lobby_box.add_child(_practice_btn)

	_session_box = VBoxContainer.new()
	_session_box.add_theme_constant_override("separation", 8)
	root.add_child(_session_box)
	_resume_btn = _button("Continuar", _hide_menu)
	_session_box.add_child(_resume_btn)
	_leave_btn = _button("Sair da sessão", func(): leave_requested.emit())
	_session_box.add_child(_leave_btn)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(410, 0)
	_status.modulate = Color(0.7, 0.9, 1.0)
	root.add_child(_status)

	var help := Label.new()
	help.text = "Teclado: W/S acelera/freia · A/D vira · Espaço pulo+drift · R reposiciona · Esc menu\n" + \
			"Controle: A/RT acelera · B/LT freia · analógico vira · RB/LB drift · Select reposiciona\n" + \
			"Drift: segure o pulo e vire. Solte após as faíscas ficarem azul/laranja/roxa para o turbo."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(410, 0)
	help.add_theme_font_size_override("font_size", 12)
	help.modulate = Color(1, 1, 1, 0.55)
	root.add_child(help)


func _build_hud() -> void:
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)

	_info = Label.new()
	_info.position = Vector2(16, 12)
	_info.add_theme_font_size_override("font_size", 14)
	_info.add_theme_constant_override("outline_size", 4)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_child(_info)

	_speed = Label.new()
	_speed.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_speed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_speed.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_speed.offset_right = -24
	_speed.offset_bottom = -16
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed.add_theme_font_size_override("font_size", 40)
	_speed.add_theme_constant_override("outline_size", 8)
	_speed.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_child(_speed)

	_drift = Label.new()
	_drift.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_drift.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_drift.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_drift.offset_bottom = -40
	_drift.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drift.add_theme_font_size_override("font_size", 32)
	_drift.add_theme_constant_override("outline_size", 8)
	_drift.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_child(_drift)

	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.offset_left = 16
	_hint.offset_bottom = -12
	_hint.text = "Esc: menu · R: reposicionar"
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.modulate = Color(1, 1, 1, 0.6)
	_hud.add_child(_hint)


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 13)
	l.modulate = Color(1, 1, 1, 0.75)
	return l


func _button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(cb)
	return b


# ----------------------------------------------------------------- ações

func _current_name() -> String:
	var n := _name_edit.text.strip_edges()
	return n if n != "" else "Piloto"


func _on_join() -> void:
	_save_settings()
	join_requested.emit(_addr_edit.text, _current_name())


func _on_host() -> void:
	_save_settings()
	host_requested.emit(_current_name())


func _on_practice() -> void:
	_save_settings()
	practice_requested.emit(_current_name())


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		_name_edit.text = cfg.get_value("player", "name", "")
		_addr_edit.text = cfg.get_value("net", "address", "")
	var from_url := Net.server_from_page_url()
	if from_url != "":
		_addr_edit.text = from_url


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", _name_edit.text)
	cfg.set_value("net", "address", _addr_edit.text)
	cfg.save(SETTINGS_PATH)
