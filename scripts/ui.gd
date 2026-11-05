extends CanvasLayer
## Interface do Rolimã: tela de título, menus em placas de madeira, seleção de pilotos,
## HUD e controles de toque.
##
## Princípios de usabilidade aplicados (desktop, controle e celular):
## - Sempre existe UM item focado ao abrir uma tela (o controle nunca fica "perdido"),
##   a navegação dá a volta (do último vai para o primeiro) e cada tela lembra o último item.
## - VOLTAR é consistente: Esc / B / pílula "VOLTAR" clicável / item VOLTAR na própria placa.
## - Ação destrutiva (sair da partida) pede confirmação, com o "NÃO" focado por padrão.
## - Texto grande com contorno grosso: lê no sofá, na TV e no celular, sobre qualquer cenário.
## - Os menus ficam por cima do mundo 3D vivo (câmera passeando pela descida), sem fundo chapado.
## - HUD de "uma olhada": tempo + progresso em cima, velocidade num canto, habilidades com recarga
##   visível e avisos curtos ("DESCIDA!", "NO AR!") só quando importam.
## - No celular: controles de toque, nada de texto de teclado, pausa grande no canto e aviso para
##   girar o aparelho quando estiver na vertical.
## - Ícones de botão acompanham o dispositivo em uso (teclado, controle ou toque).

signal join_requested(address: String, player_name: String)
signal host_requested(player_name: String)
signal practice_requested(player_name: String)
signal leave_requested

enum Screen { TITLE, MAIN, ONLINE, PILOTS, OPTIONS, HOWTO, PAUSE, CONFIRM_LEAVE, RESULTS, HUD }

const VERSION := "v0.3"
const MENU_LEFT := 84.0
const INPUT_GUARD_MS := 220
const KART_SCENE := preload("res://scenes/kart.tscn")
const AmazonThemeScript := preload("res://scripts/amazon_theme.gd")

var menu_camera: MenuCamera

var _root: Control
var _screens := {}
var _first_focus := {}
var _last_focus := {}
var _current := -1
var _stack: Array[int] = []
var _in_session := false
var _results_shown := false
var _guard_until := 0
var _t := 0.0
var _debug_capture := false ## capturas de teste não gravam recorde

var _shade: Control
var _screen_root: Control
var _prompts: PromptBar
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween
var _rotate_overlay: Control
var _touch: TouchControls
var _music: AudioStreamPlayer

var _title_logo: Control
var _title_hint: Label
var _main_info: Label
var _name_edit: LineEdit
var _addr_edit: LineEdit
var _online_status: Label
var _howto_rows: VBoxContainer
var _results_stamp: Label
var _results_time: Label
var _results_best: Label

# Pilotos
var _pilot_selector: MenuItem
var _pilot_title: Label
var _pilot_rows: VBoxContainer
var _pilot_stamp: Label
var _preview_box: SubViewportContainer
var _preview_vp: SubViewport
var _preview_pivot: Node3D
var _preview_kart: Kart
var _preview_drag := false
var _preview_yaw := 0.6

# HUD
var _hud: Control
var _timer_lbl: Label
var _progress: ProgressRope
var _speed_box: VBoxContainer
var _speed_lbl: Label
var _speed_unit: Label
var _callout: Label
var _callout_state := ""
var _callout_hold := 0.0
var _callout_tween: Tween
var _stats_lbl: Label
var _pause_btn: Button
var _abilities: AbilityHud


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UIStyle.build_theme()
	add_child(_root)

	_build_shade()
	_build_hud()
	_touch = TouchControls.new()
	_root.add_child(_touch)
	_screen_root = _full_rect_control()
	_root.add_child(_screen_root)
	_build_title()
	_build_main()
	_build_online()
	_build_pilots()
	_build_options()
	_build_howto()
	_build_pause()
	_build_confirm()
	_build_results()
	_build_prompts()
	_build_toast()
	_build_rotate_overlay()

	_music = AudioStreamPlayer.new()
	_music.stream = AmazonThemeScript.generate_amazon_stream()
	_music.volume_db = -4.0
	add_child(_music)

	Net.status_changed.connect(_on_net_status)
	GameInput.device_changed.connect(func(_d: int) -> void:
		_update_mode()
		_refresh_device_texts())
	Settings.changed.connect(_update_mode)
	get_viewport().size_changed.connect(_update_rotate_overlay)
	_refresh_device_texts()
	_update_rotate_overlay()
	_go(Screen.TITLE, false)


# =========================================================== API usada por main.gd

func show_menu(reason: String) -> void:
	_in_session = false
	_results_shown = false
	_stack.clear()
	if _current != Screen.ONLINE:
		_go(Screen.MAIN, false)
	if reason != "":
		_online_status.text = reason
		if _current != Screen.ONLINE:
			_toast_msg(reason)
	_update_mode()


func show_hud() -> void:
	_in_session = true
	_results_shown = false
	_stack.clear()
	if _toast_tween:
		_toast_tween.kill()
	_toast.visible = false
	_go(Screen.HUD, false)
	_update_mode()


func set_status(text: String) -> void:
	_on_net_status(text)


# =========================================================== navegação

func _go(s: int, push := true) -> void:
	if _current == s:
		return
	if _current >= 0:
		var fo := get_viewport().gui_get_focus_owner()
		if fo and _screens.has(_current) and (_screens[_current] as Control).is_ancestor_of(fo):
			_last_focus[_current] = fo
		if push:
			_stack.append(_current)
		if _screens.has(_current):
			(_screens[_current] as Control).visible = false
	_current = s
	_guard_until = Time.get_ticks_msec() + INPUT_GUARD_MS
	if _screens.has(s):
		_show_screen(s)
	else:
		var fo := get_viewport().gui_get_focus_owner()
		if fo:
			fo.release_focus()
	_update_prompts()
	_update_mode()


func _back() -> void:
	if _stack.is_empty():
		return
	_go(_stack.pop_back(), false)


func _show_screen(s: int) -> void:
	var c: Control = _screens[s]
	c.visible = true
	c.modulate.a = 0.0
	create_tween().tween_property(c, "modulate:a", 1.0, 0.14)
	var items := _menu_items_in(c)
	for i in items.size():
		items[i].pop_in(0.06 + i * 0.05)
	if c.has_meta("sign"):
		var sign: Control = c.get_meta("sign")
		sign.rotation = deg_to_rad(-14.0)
		sign.scale = Vector2(0.6, 0.6)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(sign, "rotation", deg_to_rad(-2.5), 0.7).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(sign, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if c.has_meta("board"):
		var board: Control = c.get_meta("board")
		var x := MENU_LEFT
		board.offset_left = x - 90.0
		create_tween().tween_property(board, "offset_left", x, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	match s:
		Screen.MAIN:
			_refresh_main_info()
		Screen.HOWTO:
			_refresh_device_texts()
		Screen.PILOTS:
			_refresh_pilot()
	var f: Control = _last_focus.get(s, _first_focus.get(s, null))
	if f and is_instance_valid(f):
		f.grab_focus.call_deferred()


func _menu_items_in(n: Node, out: Array[MenuItem] = []) -> Array[MenuItem]:
	for c in n.get_children():
		if c is MenuItem and (c as MenuItem).visible:
			out.append(c)
		_menu_items_in(c, out)
	return out


func _update_mode() -> void:
	var in_hud := _current == Screen.HUD
	_hud.visible = _in_session and (in_hud or _current == Screen.RESULTS)
	_shade.visible = not in_hud
	_touch.active = in_hud and _in_session and GameInput.device == GameInput.Device.TOUCH
	_abilities.visible = in_hud and GameInput.device != GameInput.Device.TOUCH
	_callout.visible = in_hud
	_speed_box.visible = in_hud
	_set_kart_controls(in_hud)
	get_tree().paused = _in_session and _is_offline() and not in_hud and _current != Screen.RESULTS
	if not _in_session and menu_camera and not menu_camera.current:
		menu_camera.activate()
	# Música da selva só nos menus (e só depois da primeira interação — exigência dos navegadores).
	var want_music := not _in_session and _current != Screen.TITLE
	if want_music and not _music.playing:
		_music.play()
	elif not want_music and _music.playing:
		_music.stop()
	_layout_hud()


func _is_offline() -> bool:
	var mp := multiplayer.multiplayer_peer
	return mp == null or mp is OfflineMultiplayerPeer


func _set_kart_controls(enabled: bool) -> void:
	for k in get_tree().get_nodes_in_group("local_kart"):
		k.controls_enabled = enabled


func _input(event: InputEvent) -> void:
	# Evita "clique fantasma": o mesmo toque/tecla que trocou de tela não aciona a próxima.
	if _current == Screen.HUD or Time.get_ticks_msec() >= _guard_until:
		return
	if event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventJoypadButton \
			or (event is InputEventKey and event.is_action("ui_accept")):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _current == Screen.TITLE:
		var pressed := (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton \
				or event is InputEventScreenTouch) and event.is_pressed() and not event.is_echo()
		if pressed:
			_go(Screen.MAIN, false)
			get_viewport().set_input_as_handled()
		return
	if _current == Screen.HUD:
		if event.is_action_pressed("toggle_menu"):
			_go(Screen.PAUSE)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") or (_current == Screen.PAUSE and event.is_action_pressed("toggle_menu")):
		_back()
		get_viewport().set_input_as_handled()


func _update_prompts() -> void:
	match _current:
		Screen.TITLE, Screen.HUD:
			_prompts.set_prompts([])
		Screen.MAIN:
			_prompts.set_prompts([[&"ui_accept", "SELECIONAR"]])
		Screen.PAUSE:
			_prompts.set_prompts([[&"ui_accept", "SELECIONAR"], [&"ui_cancel", "CONTINUAR"]])
		Screen.RESULTS:
			_prompts.set_prompts([[&"ui_accept", "SELECIONAR"], [&"ui_cancel", "VER A PISTA"]])
		_:
			_prompts.set_prompts([[&"ui_accept", "SELECIONAR"], [&"ui_cancel", "VOLTAR"]])
	_prompts.visible = _current != Screen.HUD and _current != Screen.TITLE


func _on_prompt(action: StringName) -> void:
	if action == &"ui_cancel":
		_back()
	elif action == &"ui_accept":
		var fo := get_viewport().gui_get_focus_owner()
		if fo is BaseButton:
			(fo as BaseButton).pressed.emit()


# =========================================================== ações

func _player_name() -> String:
	var n := _name_edit.text.strip_edges()
	return n if n != "" else "Piloto"


func _save_lobby() -> void:
	Settings.player_name = _name_edit.text.strip_edges()
	Settings.last_address = _addr_edit.text.strip_edges()
	Settings.save_settings()


func _on_practice() -> void:
	_save_lobby()
	practice_requested.emit(_player_name())


func _on_join() -> void:
	_save_lobby()
	_online_status.text = "Conectando..."
	join_requested.emit(_addr_edit.text, _player_name())


func _on_host() -> void:
	_save_lobby()
	host_requested.emit(_player_name())


func _on_restart_top() -> void:
	for k in get_tree().get_nodes_in_group("local_kart"):
		k.restart_at_top()
	_results_shown = false
	_stack.clear()
	_go(Screen.HUD, false)


func _on_leave_confirmed() -> void:
	leave_requested.emit()


func _on_net_status(text: String) -> void:
	if _online_status:
		_online_status.text = text
	# Avisos de rede só viram "toast" fora da corrida (no HUD eles só atrapalhariam a leitura).
	if not _in_session and _current != Screen.ONLINE and _current != Screen.TITLE:
		_toast_msg(text)


# =========================================================== construção: base

func _full_rect_control() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _new_screen(id: int) -> Control:
	var c := _full_rect_control()
	c.visible = false
	_screen_root.add_child(c)
	_screens[id] = c
	return c


func _build_shade() -> void:
	# Escurece só o lado esquerdo (onde ficam os menus) e mantém o mundo 3D visível à direita.
	_shade = SideShade.new()
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_shade)


## Placa de madeira com plaquinha de título pregada em cima (inclinada, estilo cartoon).
func _make_board(screen: Control, title: String, width: float) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -24)
	col.anchor_left = 0.0
	col.anchor_right = 0.0
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.offset_left = MENU_LEFT
	col.offset_right = MENU_LEFT
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	screen.add_child(col)

	var sign := PanelContainer.new()
	var sb := UIStyle.wood_box(1, true)
	sb.fill = UIStyle.WOOD_LIGHT
	sb.fill_alt = UIStyle.WOOD_LIGHT
	sb.corner_radius = 14.0
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 10
	sb.content_margin_bottom = 8
	sign.add_theme_stylebox_override("panel", sb)
	sign.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sign.z_index = 1
	sign.add_child(UIStyle.label(title, 46, UIStyle.CREAM))
	sign.resized.connect(func() -> void: sign.pivot_offset = sign.size * 0.5)
	sign.rotation = deg_to_rad(-2.5)
	col.add_child(sign)

	var board := PanelContainer.new()
	var bb := UIStyle.wood_box(5, true)
	bb.content_margin_top = 46
	bb.content_margin_left = 34
	bb.content_margin_right = 34
	bb.content_margin_bottom = 24
	board.add_theme_stylebox_override("panel", bb)
	board.custom_minimum_size.x = width
	col.add_child(board)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	board.add_child(body)
	screen.set_meta("sign", sign)
	screen.set_meta("board", col)
	return body


## Liga o foco em anel (do último volta ao primeiro) e define o item inicial.
func _link_focus(screen_id: int, items: Array[Control], first: Control = null) -> void:
	var n := items.size()
	for i in n:
		var c := items[i]
		var prev := items[(i - 1 + n) % n]
		var next := items[(i + 1) % n]
		c.focus_neighbor_top = c.get_path_to(prev)
		c.focus_neighbor_bottom = c.get_path_to(next)
		c.focus_previous = c.get_path_to(prev)
		c.focus_next = c.get_path_to(next)
		c.focus_neighbor_left = c.get_path_to(c)
		c.focus_neighbor_right = c.get_path_to(c)
	_first_focus[screen_id] = first if first else items[0]


func _item(parent: Control, text: String, cb: Callable, size_px := 44) -> MenuItem:
	var m := MenuItem.new(text, size_px)
	m.pressed.connect(cb)
	parent.add_child(m)
	return m


func _gap(parent: Control, h: float) -> void:
	var g := Control.new()
	g.custom_minimum_size.y = h
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(g)


func _make_logo(big: bool) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -20 if big else -14)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var px := 150 if big else 92
	var title := UIStyle.label("ROLIMÃ", px, UIStyle.SUN)
	title.add_theme_constant_override("outline_size", int(px * 0.27))
	title.add_theme_constant_override("shadow_outline_size", int(px * 0.27))
	title.add_theme_constant_override("shadow_offset_y", int(px * 0.08))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.rotation = deg_to_rad(-4.0)
	title.resized.connect(func() -> void: title.pivot_offset = title.size * 0.5)
	box.add_child(title)

	var plank := PanelContainer.new()
	var pb := UIStyle.wood_box(1, true)
	pb.corner_radius = 12.0
	pb.content_margin_left = 30
	pb.content_margin_right = 30
	pb.content_margin_top = 8
	pb.content_margin_bottom = 4
	plank.add_theme_stylebox_override("panel", pb)
	plank.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plank.add_child(UIStyle.label("PUMPTRACK", 50 if big else 32, UIStyle.CREAM))
	plank.rotation = deg_to_rad(2.0)
	plank.resized.connect(func() -> void: plank.pivot_offset = plank.size * 0.5)
	box.add_child(plank)
	return box


func _center(c: Control, y_offset := 0.0) -> void:
	c.set_anchors_preset(Control.PRESET_CENTER)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH
	c.offset_top = y_offset
	c.offset_bottom = y_offset


## "Chip" de papel com a tecla/ícone (usado em COMO JOGAR e PILOTOS).
func _chip(text: String, min_w := 150.0, fill := UIStyle.PAPER) -> PanelContainer:
	var chip := PanelContainer.new()
	var cb := UIStyle.paper_box(10.0)
	cb.fill = fill
	cb.fill_alt = fill
	cb.content_margin_top = 4
	cb.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", cb)
	chip.custom_minimum_size = Vector2(min_w, 0)
	chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var kl := Label.new()
	kl.text = text
	kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kl.add_theme_font_override("font", UIStyle.display_font())
	kl.add_theme_font_size_override("font_size", 22)
	kl.add_theme_color_override("font_color", UIStyle.INK)
	chip.add_child(kl)
	return chip


# =========================================================== construção: telas

func _build_title() -> void:
	var s := _new_screen(Screen.TITLE)
	_title_logo = _make_logo(true)
	_center(_title_logo, -60.0)
	s.add_child(_title_logo)
	_title_logo.resized.connect(func() -> void: _title_logo.pivot_offset = _title_logo.size * 0.5)

	_title_hint = UIStyle.label("APERTE QUALQUER BOTÃO", 40, UIStyle.CREAM)
	_title_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center(_title_hint, 190.0)
	_title_hint.resized.connect(func() -> void: _title_hint.pivot_offset = _title_hint.size * 0.5)
	s.add_child(_title_hint)

	var foot := UIStyle.label("DESCIDA DE MORRO MULTIPLAYER  ·  %s" % VERSION, 20, Color(UIStyle.CREAM, 0.8))
	foot.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	foot.grow_horizontal = Control.GROW_DIRECTION_BOTH
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.offset_bottom = -26
	s.add_child(foot)


func _build_main() -> void:
	var s := _new_screen(Screen.MAIN)
	var logo := _make_logo(false)
	logo.position = Vector2(MENU_LEFT - 18.0, 30.0)
	s.add_child(logo)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 0)
	list.position = Vector2(MENU_LEFT - 20.0, 262.0)
	s.add_child(list)
	var items: Array[Control] = []
	items.append(_item(list, "JOGAR SOZINHO", _on_practice, 42))
	items.append(_item(list, "JOGAR ONLINE", func() -> void: _go(Screen.ONLINE), 42))
	items.append(_item(list, "PILOTOS", func() -> void: _go(Screen.PILOTS), 42))
	items.append(_item(list, "COMO JOGAR", func() -> void: _go(Screen.HOWTO), 42))
	items.append(_item(list, "OPÇÕES", func() -> void: _go(Screen.OPTIONS), 42))
	if not Net.is_web() and not OS.has_feature("mobile"):
		items.append(_item(list, "SAIR DO JOGO", func() -> void: get_tree().quit(), 42))
	_link_focus(Screen.MAIN, items)

	_main_info = UIStyle.label("", 22, UIStyle.SUN)
	_main_info.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_main_info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_main_info.offset_left = MENU_LEFT
	_main_info.offset_bottom = -28
	s.add_child(_main_info)


func _refresh_main_info() -> void:
	var cdata: Dictionary = CharacterData.get_character(Settings.character)
	var txt := "PILOTO: %s" % String(cdata["name"]).to_upper()
	if Settings.best_time > 0.0:
		txt += "   ·   RECORDE: %s" % _fmt_time(Settings.best_time)
	_main_info.text = txt


func _build_online() -> void:
	var s := _new_screen(Screen.ONLINE)
	var body := _make_board(s, "JOGAR ONLINE", 640.0)
	body.add_child(UIStyle.label("SEU NOME", 24, UIStyle.SUN))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Piloto"
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size = Vector2(0, 54)
	_name_edit.text = Settings.player_name
	body.add_child(_name_edit)
	_gap(body, 8)
	body.add_child(UIStyle.label("ENDEREÇO DO HOST", 24, UIStyle.SUN))
	_addr_edit = LineEdit.new()
	_addr_edit.placeholder_text = "link do túnel  ou  localhost"
	_addr_edit.custom_minimum_size = Vector2(0, 54)
	_addr_edit.text = Settings.last_address
	var from_url := Net.server_from_page_url()
	if from_url != "":
		_addr_edit.text = from_url
	body.add_child(_addr_edit)
	_gap(body, 10)

	var items: Array[Control] = [_name_edit, _addr_edit]
	var join := _item(body, "ENTRAR NA PARTIDA", _on_join, 38)
	items.append(join)
	if not Net.is_web():
		items.append(_item(body, "CRIAR PARTIDA (HOST)", _on_host, 38))
	items.append(_item(body, "VOLTAR", _back, 38))
	_name_edit.text_submitted.connect(func(_t: String) -> void: _addr_edit.grab_focus())
	_addr_edit.text_submitted.connect(func(_t: String) -> void: join.grab_focus())

	_online_status = UIStyle.label("", 20, UIStyle.CREAM, false)
	_online_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_online_status.custom_minimum_size = Vector2(560, 0)
	body.add_child(_online_status)
	_link_focus(Screen.ONLINE, items, join)


# ----------------------------------------------------------------- PILOTOS (seleção + preview 3D)

func _build_pilots() -> void:
	var s := _new_screen(Screen.PILOTS)
	var body := _make_board(s, "PILOTOS", 620.0)

	var all := CharacterData.get_all_characters()
	var names := PackedStringArray()
	var current := 0
	for i in all.size():
		names.append(String(all[i]["name"]).to_upper())
		if all[i]["id"] == Settings.character:
			current = i
	_pilot_selector = MenuItem.new("", 40)
	_pilot_selector.set_values(names, current)
	_pilot_selector.value_changed.connect(func(i: int) -> void:
		Settings.character = all[i]["id"]
		Settings.save_settings()
		_refresh_pilot())
	body.add_child(_pilot_selector)

	_pilot_title = UIStyle.label("", 22, UIStyle.SUN, false)
	_pilot_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pilot_title.custom_minimum_size = Vector2(540, 0)
	body.add_child(_pilot_title)
	_gap(body, 8)
	_pilot_rows = VBoxContainer.new()
	_pilot_rows.add_theme_constant_override("separation", 10)
	body.add_child(_pilot_rows)
	_gap(body, 8)
	var play := _item(body, "JOGAR COM ESTE PILOTO", _on_practice, 36)
	var back := _item(body, "VOLTAR", _back, 36)
	_link_focus(Screen.PILOTS, [_pilot_selector, play, back] as Array[Control], _pilot_selector)

	# Preview 3D do carrinho + piloto, com fundo transparente por cima do mundo vivo.
	_preview_box = SubViewportContainer.new()
	_preview_box.stretch = true
	_preview_box.anchor_left = 0.58
	_preview_box.anchor_right = 0.98
	_preview_box.anchor_top = 0.1
	_preview_box.anchor_bottom = 0.86
	_preview_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_box.gui_input.connect(_on_preview_input)
	s.add_child(_preview_box)
	_preview_vp = SubViewport.new()
	_preview_vp.own_world_3d = true
	_preview_vp.transparent_bg = true
	_preview_vp.msaa_3d = Viewport.MSAA_2X
	_preview_box.add_child(_preview_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.93, 0.8)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	_preview_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	_preview_vp.add_child(sun)
	sun.look_at_from_position(Vector3(2.5, 4.5, 2.8), Vector3.ZERO, Vector3.UP)
	sun.light_energy = 1.3
	var rim := OmniLight3D.new()
	rim.position = Vector3(-2.2, 1.6, -1.5)
	rim.light_color = Color(1.0, 0.75, 0.4)
	rim.light_energy = 1.2
	rim.omni_range = 6.0
	_preview_vp.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 40.0
	_preview_vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 1.35, 3.6), Vector3(0.0, 0.42, 0.0), Vector3.UP)
	cam.current = true
	# Sombra "carimbo" redonda embaixo do carrinho (cartoon)
	var blob := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.05
	disc.bottom_radius = 1.05
	disc.height = 0.01
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(0, 0, 0, 0.35)
	disc.material = bm
	blob.mesh = disc
	blob.scale = Vector3(1.0, 1.0, 1.4)
	_preview_vp.add_child(blob)
	_preview_pivot = Node3D.new()
	_preview_pivot.position = Vector3(0, 0.02, 0)
	_preview_vp.add_child(_preview_pivot)

	_pilot_stamp = UIStyle.label("", 72, UIStyle.SUN)
	_pilot_stamp.anchor_left = 0.58
	_pilot_stamp.anchor_right = 0.98
	_pilot_stamp.anchor_top = 0.08
	_pilot_stamp.anchor_bottom = 0.08
	_pilot_stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pilot_stamp.rotation = deg_to_rad(-4.0)
	_pilot_stamp.resized.connect(func() -> void: _pilot_stamp.pivot_offset = _pilot_stamp.size * 0.5)
	_pilot_stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(_pilot_stamp)
	var hint := UIStyle.label("ARRASTE PARA GIRAR", 20, Color(UIStyle.CREAM, 0.85))
	hint.anchor_left = 0.58
	hint.anchor_right = 0.98
	hint.anchor_top = 0.86
	hint.anchor_bottom = 0.86
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(hint)


func _refresh_pilot() -> void:
	var cdata: Dictionary = CharacterData.get_character(Settings.character)
	_pilot_title.text = "%s  ·  %s" % [cdata["title"], cdata["lore_category"]]
	_pilot_stamp.text = String(cdata["name"]).to_upper()
	_pilot_stamp.add_theme_color_override("font_color", cdata["theme_color"])
	_pilot_stamp.scale = Vector2(0.5, 0.5)
	create_tween().tween_property(_pilot_stamp, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	for c in _pilot_rows.get_children():
		c.queue_free()
	var keys := _ability_keys()
	_pilot_rows.add_child(_power_row("PASSIVA", cdata["passive"], UIStyle.LEAF))
	_pilot_rows.add_child(_power_row(keys[0], cdata["ability_damage"], UIStyle.ORANGE))
	_pilot_rows.add_child(_power_row(keys[1], cdata["ability_barrier"], Color("b79bff")))

	if is_instance_valid(_preview_kart):
		_preview_kart.queue_free()
	_preview_kart = KART_SCENE.instantiate()
	_preview_kart.is_preview = true
	_preview_kart.character_id = Settings.character
	_preview_kart.rotation.y = _preview_yaw
	_preview_pivot.add_child(_preview_kart)


func _ability_keys() -> PackedStringArray:
	match GameInput.device:
		GameInput.Device.GAMEPAD:
			return PackedStringArray(["X", "Y"])
		GameInput.Device.TOUCH:
			return PackedStringArray(["ATAQUE", "ESCUDO"])
		_:
			return PackedStringArray(["Q", "E"])


func _power_row(key: String, p: Dictionary, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.add_child(_chip(key, 120.0, color.lightened(0.35)))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_txt := String(p["name"]).to_upper()
	if p.has("cooldown"):
		name_txt += "  ·  %ds" % int(p["cooldown"])
	col.add_child(UIStyle.label(name_txt, 24, UIStyle.CREAM))
	var d := UIStyle.label(p["summary"], 18, Color(UIStyle.CREAM, 0.92), false)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(400, 0)
	col.add_child(d)
	row.add_child(col)
	return row


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		_preview_drag = event.pressed
	elif event is InputEventScreenTouch:
		_preview_drag = event.pressed
	elif event is InputEventMouseMotion and _preview_drag:
		_preview_yaw += (event as InputEventMouseMotion).relative.x * 0.012
	elif event is InputEventScreenDrag:
		_preview_yaw += (event as InputEventScreenDrag).relative.x * 0.012


# ----------------------------------------------------------------- OPÇÕES

func _build_options() -> void:
	var s := _new_screen(Screen.OPTIONS)
	var body := _make_board(s, "OPÇÕES", 820.0)
	var items: Array[Control] = []

	var vol_vals := PackedStringArray()
	for i in 11:
		vol_vals.append("%d%%" % (i * 10))
	items.append(_option(body, "VOLUME", vol_vals, roundi(Settings.master_volume * 10.0), func(i: int) -> void:
		Settings.master_volume = i / 10.0))
	if Settings.can_change_window():
		items.append(_option(body, "TELA", PackedStringArray(["JANELA", "TELA CHEIA"]), 1 if Settings.fullscreen else 0, func(i: int) -> void:
			Settings.fullscreen = i == 1
			Settings.apply_video.call_deferred()))
		var res_vals := PackedStringArray()
		for r: Vector2i in Settings.RESOLUTIONS:
			res_vals.append("%d x %d" % [r.x, r.y])
		items.append(_option(body, "RESOLUÇÃO", res_vals, Settings.resolution_index, func(i: int) -> void:
			Settings.resolution_index = i
			Settings.apply_video.call_deferred()))
	items.append(_option(body, "TAMANHO DA INTERFACE", PackedStringArray(["90%", "100%", "115%", "130%"]), Settings.UI_SCALES.find(Settings.ui_scale), func(i: int) -> void:
		Settings.ui_scale = Settings.UI_SCALES[i]))
	items.append(_option(body, "TREMOR DA CÂMERA", PackedStringArray(["LIGADO", "DESLIGADO"]), 0 if Settings.camera_shake else 1, func(i: int) -> void:
		Settings.camera_shake = i == 0))
	items.append(_option(body, "MOSTRAR FPS E PING", PackedStringArray(["NÃO", "SIM"]), 1 if Settings.show_stats else 0, func(i: int) -> void:
		Settings.show_stats = i == 1))
	items.append(_option(body, "TOQUE: BOTÕES", PackedStringArray(["PEQUENOS", "MÉDIOS", "GRANDES"]), Settings.TOUCH_SCALES.find(Settings.touch_scale), func(i: int) -> void:
		Settings.touch_scale = Settings.TOUCH_SCALES[i]))
	_gap(body, 6)
	items.append(_item(body, "VOLTAR", _back, 34))
	_link_focus(Screen.OPTIONS, items)


func _option(parent: Control, caption: String, vals: PackedStringArray, idx: int, apply: Callable) -> MenuItem:
	var m := MenuItem.new(caption, 30)
	m.set_values(vals, idx if idx >= 0 else 1)
	m.value_changed.connect(func(i: int) -> void:
		apply.call(i)
		Settings.save_settings())
	parent.add_child(m)
	return m


# ----------------------------------------------------------------- COMO JOGAR

func _build_howto() -> void:
	var s := _new_screen(Screen.HOWTO)
	var body := _make_board(s, "COMO JOGAR", 820.0)
	_howto_rows = VBoxContainer.new()
	_howto_rows.add_theme_constant_override("separation", 8)
	body.add_child(_howto_rows)
	_gap(body, 6)
	var back := _item(body, "VOLTAR", _back, 36)
	_link_focus(Screen.HOWTO, [back] as Array[Control])


func _refresh_device_texts() -> void:
	if _title_hint:
		_title_hint.text = "TOQUE PARA COMEÇAR" if GameInput.device == GameInput.Device.TOUCH else "APERTE QUALQUER BOTÃO"
	if _current == Screen.PILOTS:
		_refresh_pilot()
	if _howto_rows == null:
		return
	for c in _howto_rows.get_children():
		c.queue_free()
	var rows: Array
	match GameInput.device:
		GameInput.Device.GAMEPAD:
			rows = [["A  /  RT", "empurrar o carrinho"], ["B  /  LT", "frear e dar ré"], ["ANALÓGICO", "virar com os pés"],
				["RB", "pulinho"], ["X  /  Y", "ataque e escudo do piloto"], ["SELECT", "voltar para a pista"], ["START", "pausa"]]
		GameInput.Device.TOUCH:
			rows = [["ARRASTE", "na metade esquerda para virar"], ["EMPURRA", "botão verde (segure para ganhar embalo)"], ["FREIO", "botão vermelho"],
				["PULO", "botão amarelo"], ["ATAQUE / ESCUDO", "poderes do piloto"], ["SETA", "botão azul volta para a pista"], ["II", "pausa (canto de cima)"]]
		_:
			rows = [["W  /  ↑", "empurrar o carrinho"], ["S  /  ↓", "frear e dar ré"], ["A D  /  ← →", "virar com os pés"],
				["ESPAÇO", "pulinho"], ["Q  /  E", "ataque e escudo do piloto"], ["R", "voltar para a pista"], ["ESC", "pausa"]]
	for r in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		row.add_child(_chip(r[0], 240.0))
		var l := UIStyle.label(r[1], 24, UIStyle.CREAM, false)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		_howto_rows.add_child(row)
	var tip := UIStyle.label("Segure EMPURRAR: nas descidas AZUIS o embalo cresce muito. Soltou, o carrinho vai parando. LARANJA = lombada: salta e perde velocidade!", 21, UIStyle.SUN, false)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(740, 0)
	_howto_rows.add_child(tip)


# ----------------------------------------------------------------- PAUSA / CONFIRMAÇÃO / RESULTADO

func _build_pause() -> void:
	var s := _new_screen(Screen.PAUSE)
	var body := _make_board(s, "PAUSA", 560.0)
	var items: Array[Control] = []
	items.append(_item(body, "CONTINUAR", _back, 42))
	items.append(_item(body, "VOLTAR AO TOPO", _on_restart_top, 42))
	items.append(_item(body, "COMO JOGAR", func() -> void: _go(Screen.HOWTO), 42))
	items.append(_item(body, "OPÇÕES", func() -> void: _go(Screen.OPTIONS), 42))
	items.append(_item(body, "SAIR DA PARTIDA", func() -> void: _go(Screen.CONFIRM_LEAVE), 42))
	_link_focus(Screen.PAUSE, items)


func _build_confirm() -> void:
	var s := _new_screen(Screen.CONFIRM_LEAVE)
	var body := _make_board(s, "SAIR DA PARTIDA?", 580.0)
	var msg := UIStyle.label("Você volta para o menu principal e perde esta descida.", 22, UIStyle.CREAM, false)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(500, 0)
	body.add_child(msg)
	_gap(body, 8)
	var no := _item(body, "NÃO, CONTINUAR", _back, 42)
	var yes := _item(body, "SIM, SAIR", _on_leave_confirmed, 42)
	_link_focus(Screen.CONFIRM_LEAVE, [no, yes] as Array[Control], no)


func _build_results() -> void:
	var s := _new_screen(Screen.RESULTS)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_center(col, 10.0)
	s.add_child(col)
	_results_stamp = UIStyle.label("CHEGOU!", 128, UIStyle.SUN)
	_results_stamp.add_theme_constant_override("outline_size", 34)
	_results_stamp.add_theme_constant_override("shadow_outline_size", 34)
	_results_stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_stamp.resized.connect(func() -> void: _results_stamp.pivot_offset = _results_stamp.size * 0.5)
	col.add_child(_results_stamp)
	_results_time = UIStyle.label("00:00.00", 68, UIStyle.CREAM)
	_results_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_results_time)
	_results_best = UIStyle.label("", 30, UIStyle.SKY)
	_results_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_results_best)
	_gap(col, 14)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(list)
	var again := _item(list, "DESCER DE NOVO", _on_restart_top, 42)
	var leave := _item(list, "SAIR DA PARTIDA", func() -> void: _go(Screen.CONFIRM_LEAVE), 42)
	_link_focus(Screen.RESULTS, [again, leave] as Array[Control], again)


func _show_results(kart: Kart) -> void:
	_results_shown = true
	var t := kart.finished_time
	var record := false if _debug_capture else Settings.submit_time(t)
	_results_time.text = _fmt_time(t)
	_results_best.text = "NOVO RECORDE!" if record else "RECORDE: %s" % _fmt_time(Settings.best_time)
	_results_best.add_theme_color_override("font_color", UIStyle.SUN if record else UIStyle.SKY)
	_go(Screen.RESULTS)
	_results_stamp.scale = Vector2(2.4, 2.4)
	_results_stamp.rotation = deg_to_rad(-16.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_results_stamp, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_results_stamp, "rotation", deg_to_rad(-5.0), 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


# ----------------------------------------------------------------- elementos globais

func _build_prompts() -> void:
	_prompts = PromptBar.new()
	_prompts.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_prompts.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_prompts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompts.offset_right = -30
	_prompts.offset_bottom = -24
	_prompts.prompt_pressed.connect(_on_prompt)
	_root.add_child(_prompts)


func _build_toast() -> void:
	_toast = PanelContainer.new()
	var tb := UIStyle.paper_box(14.0)
	tb.content_margin_left = 22
	tb.content_margin_right = 22
	_toast.add_theme_stylebox_override("panel", tb)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 150
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label = UIStyle.ink_label("", 22)
	_toast.add_child(_toast_label)
	_toast.visible = false
	_root.add_child(_toast)


func _toast_msg(text: String) -> void:
	_toast_label.text = text
	_toast.visible = true
	_toast.modulate.a = 0.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.18)
	_toast_tween.tween_interval(3.2)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)
	_toast_tween.tween_callback(func() -> void: _toast.visible = false)


func _build_rotate_overlay() -> void:
	_rotate_overlay = ColorRect.new()
	(_rotate_overlay as ColorRect).color = Color(UIStyle.INK, 0.94)
	_rotate_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rotate_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	_center(col)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var a := UIStyle.label("GIRE O CELULAR", 64, UIStyle.SUN)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(a)
	var b := UIStyle.label("o Rolimã é jogado na horizontal", 26, UIStyle.CREAM, false)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(b)
	_rotate_overlay.add_child(col)
	_rotate_overlay.visible = false
	_root.add_child(_rotate_overlay)


func _update_rotate_overlay() -> void:
	var sz := get_viewport().get_visible_rect().size
	_rotate_overlay.visible = GameInput.is_touch_platform() and sz.y > sz.x * 1.05


# =========================================================== HUD

func _build_hud() -> void:
	_hud = _full_rect_control()
	_hud.visible = false
	_root.add_child(_hud)

	var top := VBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 16
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(top)
	var plaque := PanelContainer.new()
	var pb := UIStyle.wood_box(1, true)
	pb.corner_radius = 14.0
	pb.content_margin_left = 28
	pb.content_margin_right = 28
	pb.content_margin_top = 8
	pb.content_margin_bottom = 4
	plaque.add_theme_stylebox_override("panel", pb)
	plaque.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer_lbl = UIStyle.label("00:00.00", 38, UIStyle.CREAM)
	_timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_lbl.custom_minimum_size.x = 190
	plaque.add_child(_timer_lbl)
	top.add_child(plaque)
	_progress = ProgressRope.new()
	_progress.custom_minimum_size = Vector2(460, 34)
	_progress.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_progress)

	_speed_box = VBoxContainer.new()
	_speed_box.add_theme_constant_override("separation", -16)
	_speed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_lbl = UIStyle.label("0", 88, UIStyle.CREAM)
	_speed_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_box.add_child(_speed_lbl)
	_speed_unit = UIStyle.label("KM/H", 28, UIStyle.SUN)
	_speed_unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_box.add_child(_speed_unit)
	_hud.add_child(_speed_box)

	_abilities = AbilityHud.new()
	_abilities.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_abilities.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_abilities.offset_left = 28
	_abilities.offset_right = 28 + 250
	_abilities.offset_top = -180
	_abilities.offset_bottom = -20
	_abilities.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_abilities)

	_callout = UIStyle.label("", 64, UIStyle.SKY)
	_callout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center(_callout, 140.0)
	_callout.resized.connect(func() -> void: _callout.pivot_offset = _callout.size * 0.5)
	_callout.modulate.a = 0.0
	_hud.add_child(_callout)

	_stats_lbl = UIStyle.label("", 18, UIStyle.CREAM, false)
	_stats_lbl.position = Vector2(20, 16)
	_hud.add_child(_stats_lbl)

	_pause_btn = Button.new()
	_pause_btn.text = "II"
	_pause_btn.focus_mode = Control.FOCUS_NONE
	_pause_btn.add_theme_font_override("font", UIStyle.display_font())
	_pause_btn.add_theme_font_size_override("font_size", 34)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_pause_btn.add_theme_color_override(k, UIStyle.INK)
	var nb := UIStyle.paper_box(38.0)
	var pressed_box := UIStyle.paper_box(38.0)
	pressed_box.fill = UIStyle.SUN
	pressed_box.shadow_offset = Vector2(0, 2)
	_pause_btn.add_theme_stylebox_override("normal", nb)
	_pause_btn.add_theme_stylebox_override("hover", nb)
	_pause_btn.add_theme_stylebox_override("pressed", pressed_box)
	_pause_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_pause_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_pause_btn.offset_left = -24 - 78
	_pause_btn.offset_right = -24
	_pause_btn.offset_top = 22
	_pause_btn.offset_bottom = 22 + 78
	_pause_btn.pressed.connect(func() -> void:
		if _current == Screen.HUD:
			_go(Screen.PAUSE))
	_hud.add_child(_pause_btn)


func _layout_hud() -> void:
	if _speed_box == null:
		return
	var touch := GameInput.device == GameInput.Device.TOUCH
	_speed_box.set_anchors_preset(Control.PRESET_TOP_RIGHT if touch else Control.PRESET_BOTTOM_RIGHT)
	_speed_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_speed_box.grow_vertical = Control.GROW_DIRECTION_END if touch else Control.GROW_DIRECTION_BEGIN
	if touch:
		# No celular o canto de baixo é dos botões: velocidade sobe para perto da pausa.
		_speed_box.offset_right = -24 - 78 - 22
		_speed_box.offset_left = _speed_box.offset_right
		_speed_box.offset_top = 6
		_speed_box.offset_bottom = 6
		_speed_lbl.add_theme_font_size_override("font_size", 60)
		_speed_unit.add_theme_font_size_override("font_size", 22)
	else:
		_speed_box.offset_right = -32
		_speed_box.offset_left = -32
		_speed_box.offset_bottom = -18
		_speed_box.offset_top = -18
		_speed_lbl.add_theme_font_size_override("font_size", 88)
		_speed_unit.add_theme_font_size_override("font_size", 28)


func _process(delta: float) -> void:
	_t += delta
	if _current == Screen.TITLE:
		_title_logo.rotation = sin(_t * 1.6) * 0.025
		_title_logo.scale = Vector2.ONE * (1.0 + sin(_t * 2.2) * 0.015)
		_title_hint.modulate.a = 0.55 + 0.45 * absf(sin(_t * 2.6))
		_title_hint.scale = Vector2.ONE * (1.0 + absf(sin(_t * 2.6)) * 0.05)
	elif _current == Screen.PILOTS and is_instance_valid(_preview_kart):
		if not _preview_drag:
			_preview_yaw += delta * 0.45
		_preview_kart.rotation.y = _preview_yaw
	if _in_session:
		_set_kart_controls(_current == Screen.HUD)
	if not _hud.visible:
		return

	var kart := get_tree().get_first_node_in_group("local_kart") as Kart
	var world := get_tree().current_scene.get_node_or_null("World")
	var online := not _is_offline()
	var players := get_tree().get_nodes_in_group("karts").size()
	var lines: PackedStringArray = []
	if online:
		lines.append("%s · %d PILOTOS" % ["HOST" if multiplayer.is_server() else "ONLINE", players])
	if Settings.show_stats:
		lines.append("%d FPS%s" % [Engine.get_frames_per_second(), "" if Net.ping_ms < 0 else " · %d ms" % Net.ping_ms])
	_stats_lbl.text = "\n".join(lines)
	_touch.kart = kart
	_abilities.kart = kart
	_abilities.queue_redraw()
	if kart == null:
		return

	var ratio := kart.get_speed_ratio()
	_speed_lbl.text = str(roundi(kart.get_speed_kmh()))
	var sc := UIStyle.CREAM.lerp(UIStyle.SUN, clampf(ratio * 1.4 - 0.4, 0.0, 1.0))
	if ratio > 1.15:
		sc = UIStyle.SUN.lerp(UIStyle.ORANGE, clampf((ratio - 1.15) * 3.0, 0.0, 1.0))
	_speed_lbl.add_theme_color_override("font_color", sc)

	var t := kart.finished_time if kart.finished_time > 0.0 else kart.race_time
	_timer_lbl.text = _fmt_time(t)

	if world and world.has_method("compute_progress"):
		var markers: Array = []
		for k in get_tree().get_nodes_in_group("karts"):
			var kk := k as Kart
			var is_me := kk == kart
			var col: Color = Kart.KART_COLORS[kk.slot % Kart.KART_COLORS.size()]
			var entry := [world.compute_progress(kk.ball.global_position), col, is_me]
			if is_me:
				markers.append(entry)
			else:
				markers.push_front(entry)
		_progress.markers = markers
		_progress.queue_redraw()

	if kart.finished_time > 0.0 and not _results_shown and _current == Screen.HUD:
		_show_results(kart)

	_update_callout(kart, delta)


func _update_callout(kart: Kart, delta: float) -> void:
	var st := ""
	if not kart.grounded and kart.air_time > 0.25:
		st = "air"
	elif kart.slope_grade > 0.11 and kart.fwd_speed > 10.0:
		st = "down"
	elif kart.slope_grade < -0.05 and kart.fwd_speed > 8.0:
		st = "up"
	if st != "":
		_callout_hold = 0.45
	else:
		_callout_hold -= delta
	if st != "" and st != _callout_state:
		_callout_state = st
		match st:
			"air":
				_callout.text = "NO AR!"
				_callout.add_theme_color_override("font_color", UIStyle.ORANGE)
			"down":
				_callout.text = "DESCIDA!"
				_callout.add_theme_color_override("font_color", UIStyle.SKY)
			"up":
				_callout.text = "LOMBADA!"
				_callout.add_theme_color_override("font_color", UIStyle.SUN)
		if _callout_tween:
			_callout_tween.kill()
		_callout.modulate.a = 1.0
		_callout.scale = Vector2(0.4, 0.4)
		_callout.rotation = deg_to_rad(randf_range(-5.0, 5.0))
		_callout_tween = create_tween()
		_callout_tween.tween_property(_callout, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif st == "" and _callout_state != "" and _callout_hold <= 0.0:
		_callout_state = ""
		if _callout_tween:
			_callout_tween.kill()
		_callout_tween = create_tween()
		_callout_tween.tween_property(_callout, "modulate:a", 0.0, 0.25)


static func _fmt_time(t: float) -> String:
	var mins := int(t) / 60
	return "%02d:%05.2f" % [mins, fmod(t, 60.0)]


# =========================================================== depuração (capturas de tela)

func _debug_touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.position = pos
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _debug_drag(idx: int, pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = idx
	ev.position = pos
	ev.relative = Vector2(-8, 0)
	Input.parse_input_event(ev)


## godot --path . -- --ui-shot=main --shot-out=C:/tmp/main.png [--fake-touch]
func debug_capture(screen_name: String, out_path: String) -> void:
	_debug_capture = true
	await get_tree().process_frame
	var needs_session := screen_name in ["hud", "pause", "confirm", "results", "touchtest", "coast"]
	if screen_name != "title":
		_go(Screen.MAIN, false)
	if needs_session:
		practice_requested.emit("Teste")
		await get_tree().process_frame
		if screen_name == "hud":
			Input.action_press(&"accelerate")
			Input.action_press(&"steer_left", 0.3)
	match screen_name:
		"online":
			_go(Screen.ONLINE)
		"pilots":
			_go(Screen.PILOTS)
		"options":
			_go(Screen.OPTIONS)
		"howto":
			_go(Screen.HOWTO)
		"pause":
			_go(Screen.PAUSE)
		"confirm":
			_go(Screen.PAUSE)
			_go(Screen.CONFIRM_LEAVE)
		"results":
			var k := get_tree().get_first_node_in_group("local_kart") as Kart
			if k:
				k.finished_time = 161.37
		"coast":
			# Sem nenhuma entrada: o carrinho não pode sair descendo sozinho.
			var kc := get_tree().get_first_node_in_group("local_kart") as Kart
			for i in 6:
				await get_tree().create_timer(1.0, true, false, true).timeout
				print("[COAST] t=", i + 1, "s kmh=", kc.get_speed_kmh(), " slope=", kc.slope_grade)
			Input.action_press(&"accelerate")
			for i in 4:
				await get_tree().create_timer(1.0, true, false, true).timeout
				print("[PUSH] t=", i + 1, "s kmh=", kc.get_speed_kmh(), " slope=", kc.slope_grade)
			Input.action_release(&"accelerate")
			for i in 4:
				await get_tree().create_timer(1.0, true, false, true).timeout
				print("[RELEASE] t=", i + 1, "s kmh=", kc.get_speed_kmh(), " slope=", kc.slope_grade)
		"touchtest":
			# Simula um polegar: segura EMPURRA e arrasta o analógico para a esquerda.
			await get_tree().create_timer(3.0, true, false, true).timeout
			var k := get_tree().get_first_node_in_group("local_kart") as Kart
			var sz := get_viewport().get_visible_rect().size
			var start := Vector2(220, sz.y - 170)
			_debug_touch(0, start, true)
			_debug_touch(1, Vector2(sz.x - 142, sz.y - 142), true)
			for i in 12:
				await get_tree().physics_frame
				_debug_drag(0, start + Vector2(-8.0 * (i + 1), 0))
			for i in 40:
				await get_tree().physics_frame
			print("[TOUCH] active=", _touch.active, " touch_steer=", GameInput.touch_steer,
					" accel=", GameInput.strength(&"accelerate"), " kart.steer=", k.steer if k else -99.0,
					" kmh=", k.get_speed_kmh() if k else -1.0, " device=", GameInput.device)
	await get_tree().create_timer(6.0 if screen_name == "hud" else 3.5, true, false, true).timeout
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(out_path)
	print("[UI] captura salva em ", out_path)
	get_tree().quit()


# =========================================================== barra de progresso (corda)

class ProgressRope:
	extends Control
	## Corda da largada até a bandeira, com a bolinha de cada piloto (a sua é maior).

	var markers: Array = [] ## [[ratio, cor, é_o_jogador_local], ...]

	func _draw() -> void:
		var y := size.y * 0.5
		var x0 := 12.0
		var x1 := size.x - 34.0
		draw_line(Vector2(x0, y + 4), Vector2(x1, y + 4), Color(0, 0, 0, 0.35), 12.0, true)
		draw_line(Vector2(x0, y), Vector2(x1, y), UIStyle.INK, 12.0, true)
		draw_line(Vector2(x0, y), Vector2(x1, y), UIStyle.WOOD_LIGHT, 6.0, true)
		for i in 10:
			var x := lerpf(x0, x1, (i + 0.5) / 10.0)
			draw_line(Vector2(x - 3, y - 3), Vector2(x + 3, y + 3), Color(UIStyle.INK, 0.55), 2.0, true)
		# bandeira quadriculada de chegada
		var fx := x1 + 6.0
		draw_line(Vector2(fx, y + 12), Vector2(fx, y - 15), UIStyle.INK, 4.0, true)
		var cell := 6.0
		var flag := Rect2(fx + 1, y - 16, cell * 4, cell * 3)
		draw_rect(flag.grow(2), UIStyle.INK)
		for cx in 4:
			for cy in 3:
				var c := UIStyle.CREAM if (cx + cy) % 2 == 0 else UIStyle.INK
				draw_rect(Rect2(flag.position + Vector2(cx, cy) * cell, Vector2(cell, cell)), c)
		draw_circle(Vector2(x0, y), 7.0, UIStyle.INK)
		draw_circle(Vector2(x0, y), 4.0, UIStyle.LEAF)
		for m in markers:
			var x := lerpf(x0, x1, float(m[0]))
			var r := 11.0 if m[2] else 7.0
			draw_circle(Vector2(x, y + 2), r + 3.0, Color(0, 0, 0, 0.35))
			draw_circle(Vector2(x, y), r + 3.0, UIStyle.INK)
			draw_circle(Vector2(x, y), r, m[1])


# =========================================================== habilidades no HUD (teclado/controle)

class AbilityHud:
	extends Control
	## Nome do piloto + dois "medalhões" (ataque e escudo) com recarga em pizza e a tecla embaixo.

	var kart: Kart

	func _draw() -> void:
		if kart == null:
			return
		var font := UIStyle.display_font()
		var cdata: Dictionary = CharacterData.get_character(kart.character_id)
		var name_txt := String(cdata["name"]).to_upper()
		var base_y := size.y - 28.0
		_text(font, name_txt, Vector2(4, 24), 26, cdata["theme_color"], false)
		var keys := ["X", "Y"] if GameInput.device == GameInput.Device.GAMEPAD else ["Q", "E"]
		var specs := [
			[kart.damage_cooldown, kart.damage_max_cooldown, UIStyle.ORANGE, "ATAQUE", false],
			[kart.barrier_cooldown, kart.barrier_max_cooldown, Color("9a6cff"), "ESCUDO", kart.is_barrier_active()],
		]
		for i in 2:
			var c := Vector2(48 + i * 108, base_y - 44)
			var r := 38.0
			var left: float = specs[i][0]
			var total: float = specs[i][1]
			var col: Color = specs[i][2]
			var active: bool = specs[i][4]
			draw_circle(c + Vector2(0, 5), r, Color(0, 0, 0, 0.35))
			draw_circle(c, r, UIStyle.INK)
			draw_circle(c, r - 5, col if left <= 0.0 else col.darkened(0.45))
			draw_circle(c + Vector2(0, -r * 0.38), r * 0.42, Color(1, 1, 1, 0.16))
			if active:
				draw_arc(c, r + 4, 0, TAU, 40, UIStyle.SKY, 6.0, true)
			if left > 0.0:
				var frac := clampf(left / maxf(total, 0.01), 0.0, 1.0)
				var pts := PackedVector2Array([c])
				for k in 25:
					var ang := -PI * 0.5 + TAU * frac * float(k) / 24.0
					pts.append(c + Vector2(cos(ang), sin(ang)) * (r - 5))
				draw_colored_polygon(pts, Color(UIStyle.INK, 0.55))
				_text(font, str(ceili(left)), c + Vector2(0, 10), 30, UIStyle.CREAM, true)
			else:
				_text(font, specs[i][3], c + Vector2(0, 7), 15, UIStyle.CREAM, true)
			# tecla embaixo do medalhão
			var kc := Rect2(c.x - 18, c.y + r + 2, 36, 28)
			draw_colored_polygon(CartoonBox.rounded_points(kc, 7.0), UIStyle.INK)
			draw_colored_polygon(CartoonBox.rounded_points(kc.grow(-3), 5.0), UIStyle.CREAM)
			_text(font, keys[i], Vector2(c.x, kc.position.y + 22), 20, UIStyle.INK, true, false)

	func _text(font: Font, t: String, pos: Vector2, px: int, color: Color, centered: bool, outline := true) -> void:
		var p := pos
		if centered:
			p.x -= font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x * 0.5
		if outline:
			draw_string_outline(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, maxi(6, int(px * 0.32)), UIStyle.INK)
		draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)


# =========================================================== sombreado lateral dos menus

class SideShade:
	extends Control
	## Degradê escuro da esquerda para a direita (dá contraste às placas sem esconder o mundo).

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var a := Color(UIStyle.INK, 0.7)
		var b := Color(UIStyle.INK, 0.38)
		var c := Color(UIStyle.INK, 0.0)
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.42, 0), Vector2(w * 0.42, h), Vector2(0, h)]),
				PackedColorArray([a, b, b, a]))
		draw_polygon(PackedVector2Array([Vector2(w * 0.42, 0), Vector2(w * 0.85, 0), Vector2(w * 0.85, h), Vector2(w * 0.42, h)]),
				PackedColorArray([b, c, c, b]))
