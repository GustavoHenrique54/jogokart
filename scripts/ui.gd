extends CanvasLayer
## Lobby inspirado em Crash Team Rumble / Kart Arcade clássico de PS1 com tema da Floresta e Cultura Brasileira.
## Cenário 3D interativo na Floresta Tropical: arraste com o botão direito para girar a câmera e olhar em volta.
## Aba de Controles idêntica ao design do Aku Aku (madeira + pergaminho) no lugar dos personagens.
## Trilha sonora procedural contínua com tema da Floresta Amazônica tocando no lobby.

signal join_requested(address: String, player_name: String)
signal host_requested(player_name: String)
signal practice_requested(player_name: String)
signal leave_requested

const SETTINGS_PATH := "user://settings.cfg"
const CharacterDataScript := preload("res://scripts/character_data.gd")
const AmazonThemeScript := preload("res://scripts/amazon_theme.gd")
const KART_SCENE := preload("res://scenes/kart.tscn")

const RESOLUTIONS := [
	Vector2i(1920, 1080),
	Vector2i(1600, 900),
	Vector2i(1280, 720),
	Vector2i(1024, 576),
	Vector2i(800, 600)
]

# Layout Principal (Lobby)
var _lobby_screen: Control
var _multiplayer_dialog: PanelContainer
var _name_edit: LineEdit
var _top_name_edit: LineEdit
var _addr_edit: LineEdit
var _status_lbl: Label

# Coluna Esquerda: Botões estilo Crash
var _btn_play: Button
var _btn_heroes: Button
var _btn_powers: Button
var _btn_multiplayer: Button
var _btn_controls: Button

# Centro: Abas Alternáveis (Heróis 3D vs Painel de Controles & Ajustes)
var _center_col: VBoxContainer
var _center_heroes_view: VBoxContainer
var _center_controls_view: VBoxContainer

# Cenário 3D da Floresta do PS1 + Carrinho e Herói sem plataforma
var _preview_viewport_container: SubViewportContainer
var _preview_viewport: SubViewport
var _preview_camera: Camera3D
var _preview_jungle_root: Node3D
var _preview_pivot: Node3D
var _preview_kart: Kart
var _char_btn_boitata: Button
var _char_btn_et: Button

# Controle Orbital da Câmera pelo Botão Direito do Mouse
var _is_orbiting: bool = false
var _cam_yaw: float = 0.0
var _cam_pitch: float = deg_to_rad(12.0)
var _cam_dist: float = 2.65
var _cam_target: Vector3 = Vector3(0.0, 0.36, 0.0)

# Controles & Configurações (Aba no lugar dos heróis)
var _vol_slider: HSlider
var _vol_lbl: Label
var _window_mode_option: OptionButton
var _res_option: OptionButton

# Trilha Sonora Tema Floresta Amazônica do Lobby
var _lobby_music_player: AudioStreamPlayer

# Coluna Direita: Pergaminho do Aku Aku com Topo de Madeira e Badges
var _aku_panel: PanelContainer
var _wood_title: Label
var _scroll_subtitle: Label
var _badges_row: HBoxContainer
var _passive_card: PanelContainer
var _passive_name: Label
var _passive_desc: Label
var _damage_card: PanelContainer
var _damage_name: Label
var _damage_meta: Label
var _damage_desc: Label
var _barrier_card: PanelContainer
var _barrier_name: Label
var _barrier_meta: Label
var _barrier_desc: Label
var _confirm_btn: Button

# Estado de seleção
var _selected_character_id: String = CharacterDataScript.BOITATA

# Menu de Pausa (In-Game)
var _pause_menu: PanelContainer
var _resume_btn: Button
var _restart_btn: Button
var _leave_btn: Button

# HUD In-Game
var _hud: Control
var _info: Label
var _timer_lbl: Label
var _speed: Label
var _slope_lbl: Label
var _hint: Label
var _hud_char_banner: Label
var _hud_passive_lbl: Label
var _hud_damage_btn: PanelContainer
var _hud_damage_lbl: Label
var _hud_damage_cd_lbl: Label
var _hud_barrier_btn: PanelContainer
var _hud_barrier_lbl: Label
var _hud_barrier_cd_lbl: Label


func _ready() -> void:
	_setup_lobby_music()
	_build_lobby()
	_build_multiplayer_dialog()
	_build_pause_menu()
	_build_hud()
	_load_settings()
	Net.status_changed.connect(set_status)
	show_menu("")


func _setup_lobby_music() -> void:
	_lobby_music_player = AudioStreamPlayer.new()
	_lobby_music_player.bus = "Master"
	_lobby_music_player.stream = AmazonThemeScript.generate_amazon_stream()
	add_child(_lobby_music_player)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed:
			_is_orbiting = false

	if event.is_action_pressed("toggle_menu"):
		if Net.in_session:
			if _pause_menu.visible:
				_hide_pause()
			else:
				_show_pause()
			get_viewport().set_input_as_handled()


func set_status(text: String) -> void:
	if _status_lbl:
		_status_lbl.text = text


func show_menu(reason: String) -> void:
	_lobby_screen.visible = true
	_pause_menu.visible = false
	_hud.visible = false
	_multiplayer_dialog.visible = false
	if reason != "":
		set_status(reason)
	_set_kart_controls(false)
	_reload_preview_kart()
	if _lobby_music_player and not _lobby_music_player.playing:
		_lobby_music_player.play()


func show_hud() -> void:
	_lobby_screen.visible = false
	_pause_menu.visible = false
	_multiplayer_dialog.visible = false
	_hud.visible = true
	_set_kart_controls(true)
	if _lobby_music_player and _lobby_music_player.playing:
		_lobby_music_player.stop()


func _show_pause() -> void:
	_pause_menu.visible = true
	_set_kart_controls(false)
	_resume_btn.grab_focus()


func _hide_pause() -> void:
	_pause_menu.visible = false
	_set_kart_controls(true)


func _set_kart_controls(enabled: bool) -> void:
	for k in get_tree().get_nodes_in_group("local_kart"):
		k.controls_enabled = enabled


func _process(delta: float) -> void:
	# Rotação suave contínua da câmera orbital no lobby (se o usuário não estiver arrastando com botão direito)
	if _lobby_screen.visible and _center_heroes_view and _center_heroes_view.visible:
		if not _is_orbiting:
			_cam_yaw += delta * 0.16
			_update_preview_camera()

	if not _hud.visible:
		return

	var kart := get_tree().get_first_node_in_group("local_kart") as Kart
	var world := get_tree().current_scene.get_node_or_null("World")
	var role := "Treino offline"
	var mp := multiplayer.multiplayer_peer
	if mp and not (mp is OfflineMultiplayerPeer):
		role = "Host" if multiplayer.is_server() else "Cliente"
	var players := get_tree().get_nodes_in_group("karts").size()
	var ping := "" if Net.ping_ms < 0 else " · ping %d ms" % Net.ping_ms
	_info.text = "%s · %d no morro%s · %d FPS" % [role, players, ping, Engine.get_frames_per_second()]

	if kart:
		kart.controls_enabled = not _pause_menu.visible
		_speed.text = "%d km/h" % roundi(kart.get_speed_kmh())

		var prog := 0.0
		if world and world.has_method("compute_progress"):
			prog = world.compute_progress(kart.ball.global_position) * 100.0
		var t := kart.finished_time if kart.finished_time > 0.0 else kart.race_time
		var mins := int(t) / 60
		var secs := fmod(t, 60.0)
		if kart.finished_time > 0.0:
			_timer_lbl.text = "CHEGOU! Tempo: %02d:%05.2f  (Esc -> Menu)" % [mins, secs]
			_timer_lbl.modulate = Color(1.0, 0.88, 0.25)
		else:
			_timer_lbl.text = "Descida: %0.0f%%  ·  Tempo: %02d:%05.2f" % [prog, mins, secs]
			_timer_lbl.modulate = Color.WHITE

		if not kart.grounded and kart.air_time > 0.14:
			_slope_lbl.text = "NO AR! (gravidade folclórica)"
			_slope_lbl.modulate = Color(1.0, 0.55, 0.2)
		elif kart.slope_grade > 0.095:
			_slope_lbl.text = "DECLIVE FORTE! +++ VELOCIDADE"
			_slope_lbl.modulate = Color(0.25, 0.9, 1.0)
		elif kart.slope_grade < -0.025:
			_slope_lbl.text = "ACLIVE / LOMBADA! (atenção ao relevo)"
			_slope_lbl.modulate = Color(1.0, 0.65, 0.25)
		else:
			_slope_lbl.text = ""

		_update_hud_abilities(kart)


func _update_hud_abilities(kart: Kart) -> void:
	var cdata: Dictionary = CharacterDataScript.get_character(kart.character_id)
	_hud_char_banner.text = "%s %s" % [cdata.passive.icon, cdata.name]
	_hud_char_banner.modulate = cdata.theme_color
	_hud_passive_lbl.text = "Passiva: %s" % cdata.passive.name

	if kart.damage_cooldown <= 0.0:
		_hud_damage_cd_lbl.text = "PRONTA [Q]"
		_hud_damage_cd_lbl.modulate = Color(0.35, 1.0, 0.45)
	else:
		_hud_damage_cd_lbl.text = "[Q] %.1fs" % kart.damage_cooldown
		_hud_damage_cd_lbl.modulate = Color(1.0, 0.7, 0.3)

	if kart.is_barrier_active():
		_hud_barrier_cd_lbl.text = "ATIVA! %.1fs" % kart.barrier_time_left
		_hud_barrier_cd_lbl.modulate = Color(0.2, 0.95, 1.0)
	elif kart.barrier_cooldown <= 0.0:
		_hud_barrier_cd_lbl.text = "PRONTA [E]"
		_hud_barrier_cd_lbl.modulate = Color(0.35, 1.0, 0.45)
	else:
		_hud_barrier_cd_lbl.text = "[E] %.1fs" % kart.barrier_cooldown
		_hud_barrier_cd_lbl.modulate = Color(1.0, 0.7, 0.3)


# ================================================================= CONSTRUÇÃO DO LOBBY

func _build_lobby() -> void:
	_lobby_screen = Control.new()
	_lobby_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_lobby_screen)

	# Fundo: Floresta Tropical de PS1 (Degradê de copa de árvores e céu tropical)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.22, 0.14, 0.95) # Verde floresta densa
	_lobby_screen.add_child(bg)

	# Layout geral vertical
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 10)
	main_vbox.offset_left = 20
	main_vbox.offset_top = 12
	main_vbox.offset_right = -20
	main_vbox.offset_bottom = -12
	_lobby_screen.add_child(main_vbox)

	# 1. Top Bar com Perfil estilo Crash
	_build_top_bar(main_vbox)

	# 2. Área Central: 3 Colunas (Menu Esquerdo, Centro com Heróis 3D ou Controles, Pergaminho do Aku Aku à Direita)
	var content_row := HBoxContainer.new()
	content_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_row.add_theme_constant_override("separation", 16)
	main_vbox.add_child(content_row)

	# Coluna Esquerda: Botões
	_build_left_column(content_row)

	# Coluna Central: Floresta Tropical 3D (Botão Direito gira câmera) OU Aba de Controles
	_build_center_column(content_row)

	# Coluna Direita: Caixa de Texto Idêntica ao Print do Aku Aku
	_build_right_column(content_row)

	# Rodapé de Legenda Externa (como no print)
	var footer_lbl := Label.new()
	footer_lbl.text = "Jogo entre plataformas habilitado. Você pode encontrar jogadores de outras plataformas."
	footer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer_lbl.add_theme_font_size_override("font_size", 11)
	footer_lbl.modulate = Color(0.75, 0.9, 1.0, 0.75)
	main_vbox.add_child(footer_lbl)


func _build_top_bar(parent: Control) -> void:
	var top_bar := HBoxContainer.new()
	top_bar.custom_minimum_size = Vector2(0, 52)
	parent.add_child(top_bar)

	var logo_box := VBoxContainer.new()
	logo_box.add_theme_constant_override("separation", -3)
	top_bar.add_child(logo_box)

	var title_lbl := Label.new()
	title_lbl.text = "ROLIMÃ PUMPTRACK"
	title_lbl.add_theme_font_size_override("font_size", 26)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.15))
	title_lbl.add_theme_constant_override("outline_size", 6)
	title_lbl.add_theme_color_override("font_outline_color", Color(0.08, 0.22, 0.52))
	logo_box.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "🌴 FLORESTA DO FOLCLORE BRASILEIRO 🌴"
	sub_lbl.add_theme_font_size_override("font_size", 11)
	sub_lbl.add_theme_color_override("font_color", Color(0.25, 0.92, 0.45))
	logo_box.add_child(sub_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)

	# Card de Perfil estilo Crash
	var profile_card := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.08, 0.18, 0.38, 0.92)
	psb.set_corner_radius_all(10)
	psb.border_width_left = 2
	psb.border_width_right = 2
	psb.border_width_top = 2
	psb.border_width_bottom = 2
	psb.border_color = Color(1.0, 0.82, 0.15)
	psb.set_content_margin_all(6)
	profile_card.add_theme_stylebox_override("panel", psb)
	top_bar.add_child(profile_card)

	var prof_row := HBoxContainer.new()
	prof_row.add_theme_constant_override("separation", 8)
	profile_card.add_child(prof_row)

	var avatar_icon := Label.new()
	avatar_icon.text = "🇧🇷"
	avatar_icon.add_theme_font_size_override("font_size", 22)
	prof_row.add_child(avatar_icon)

	var prof_col := VBoxContainer.new()
	prof_col.add_theme_constant_override("separation", 1)
	prof_row.add_child(prof_col)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	prof_col.add_child(name_row)

	var piloto_lbl := Label.new()
	piloto_lbl.text = "Piloto:"
	piloto_lbl.add_theme_font_size_override("font_size", 11)
	piloto_lbl.modulate = Color(1, 1, 1, 0.6)
	name_row.add_child(piloto_lbl)

	_top_name_edit = LineEdit.new()
	_top_name_edit.placeholder_text = "Seu Nome"
	_top_name_edit.text = "Piloto"
	_top_name_edit.max_length = 16
	_top_name_edit.custom_minimum_size = Vector2(100, 22)
	_top_name_edit.text_changed.connect(func(new_text: String):
		if _name_edit:
			_name_edit.text = new_text
		_save_settings()
	)
	name_row.add_child(_top_name_edit)

	var xp_lbl := Label.new()
	xp_lbl.text = "⭐ NÍVEL 1 · SELVA DO MORRO"
	xp_lbl.add_theme_font_size_override("font_size", 9)
	xp_lbl.modulate = Color(0.25, 0.9, 1.0)
	prof_col.add_child(xp_lbl)


func _build_left_column(parent: Control) -> void:
	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(230, 0)
	left_col.add_theme_constant_override("separation", 10)
	parent.add_child(left_col)

	# 1. BOTÃO JOGAR (Grande, Amarelo com Borda Azul como no Crash)
	_btn_play = _create_crash_button("JOGAR", true, true)
	_btn_play.custom_minimum_size = Vector2(230, 64)
	_btn_play.pressed.connect(_on_practice)
	left_col.add_child(_btn_play)

	# 2. BOTÃO HERÓIS (Aba de Heróis em Destaque Dourado/Selecionado)
	_btn_heroes = _create_crash_button("✦ HERÓIS ✦", true, false)
	_btn_heroes.pressed.connect(_show_heroes_tab)
	left_col.add_child(_btn_heroes)

	# 3. BOTÃO PODERES
	_btn_powers = _create_crash_button("PODERES", false, false)
	_btn_powers.pressed.connect(_show_powers_focus)
	left_col.add_child(_btn_powers)

	# 4. BOTÃO MULTIPLAYER
	_btn_multiplayer = _create_crash_button("MULTIPLAYER", false, false)
	_btn_multiplayer.pressed.connect(func(): _multiplayer_dialog.visible = true)
	left_col.add_child(_btn_multiplayer)

	# 5. BOTÃO CONTROLES (Abre a aba no lugar dos personagens)
	_btn_controls = _create_crash_button("CONTROLES", false, false)
	_btn_controls.pressed.connect(_show_controls_tab)
	left_col.add_child(_btn_controls)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_child(spacer)

	# Banner inferior esquerdo (Card Beta do Crash adaptado)
	var beta_banner := PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.06, 0.16, 0.18, 0.92)
	bsb.set_corner_radius_all(10)
	bsb.border_width_left = 3
	bsb.border_color = Color(0.2, 0.9, 0.45)
	bsb.set_content_margin_all(8)
	beta_banner.add_theme_stylebox_override("panel", bsb)
	left_col.add_child(beta_banner)

	var b_vbox := VBoxContainer.new()
	b_vbox.add_theme_constant_override("separation", 2)
	beta_banner.add_child(b_vbox)

	var b_tag := Label.new()
	b_tag.text = "SELVA BRASILEIRA"
	b_tag.add_theme_font_size_override("font_size", 11)
	b_tag.add_theme_color_override("font_color", Color(1.0, 0.82, 0.15))
	b_vbox.add_child(b_tag)

	_status_lbl = Label.new()
	_status_lbl.text = "Boitatá & ET nas pistas de rolimã da floresta!"
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.add_theme_font_size_override("font_size", 10)
	_status_lbl.modulate = Color(1, 1, 1, 0.75)
	b_vbox.add_child(_status_lbl)


# ================================================================= COLUNA CENTRAL (HERÓIS 3D OU CONTROLES)

func _build_center_column(parent: Control) -> void:
	_center_col = VBoxContainer.new()
	_center_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center_col.add_theme_constant_override("separation", 8)
	parent.add_child(_center_col)

	# --- ABA 1: CENÁRIO 3D DOS HERÓIS NA SELVA (COM ROTAÇÃO POR BOTÃO DIREITO) ---
	_center_heroes_view = VBoxContainer.new()
	_center_heroes_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center_heroes_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center_heroes_view.add_theme_constant_override("separation", 8)
	_center_col.add_child(_center_heroes_view)

	# Container de Viewport 3D
	_preview_viewport_container = SubViewportContainer.new()
	_preview_viewport_container.stretch = true
	_preview_viewport_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_viewport_container.custom_minimum_size = Vector2(340, 360)
	_preview_viewport_container.gui_input.connect(_on_preview_gui_input)
	_center_heroes_view.add_child(_preview_viewport_container)

	_preview_viewport = SubViewport.new()
	_preview_viewport.own_world_3d = true
	_preview_viewport.transparent_bg = true
	_preview_viewport.msaa_3d = Viewport.MSAA_2X
	_preview_viewport_container.add_child(_preview_viewport)

	# Câmera 3D orbital
	_preview_camera = Camera3D.new()
	_preview_viewport.add_child(_preview_camera)
	_preview_camera.current = true
	_update_preview_camera()

	# Dica visual flutuante sobre a rotação da câmera
	var cam_hint := Label.new()
	cam_hint.text = "🖱️ Botão Direito: Arraste para Girar o Cenário 3D  ·  Roda: Zoom"
	cam_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	cam_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cam_hint.add_theme_font_size_override("font_size", 11)
	cam_hint.add_theme_constant_override("outline_size", 4)
	cam_hint.add_theme_color_override("font_outline_color", Color(0.04, 0.1, 0.2))
	cam_hint.modulate = Color(1.0, 0.9, 0.35, 0.9)
	cam_hint.position = Vector2(0, -24)
	_preview_viewport_container.add_child(cam_hint)

	# Iluminação Quente de Selva PS1 (Crash Bandicoot 1 / Jungle Rollers)
	var light_sun := DirectionalLight3D.new()
	light_sun.look_at_from_position(Vector3(2.5, 4.5, 2.8), Vector3.ZERO, Vector3.UP)
	light_sun.light_color = Color(1.0, 0.95, 0.8)
	light_sun.light_energy = 1.35
	_preview_viewport.add_child(light_sun)

	var light_fill := OmniLight3D.new()
	light_fill.position = Vector3(-2.0, 1.8, 1.2)
	light_fill.light_color = Color(0.25, 0.75, 0.45) # Brilho verde-esmeralda da mata
	light_fill.light_energy = 0.85
	light_fill.omni_range = 7.0
	_preview_viewport.add_child(light_fill)

	# Raiz da Floresta do PS1 (SEM NENHUMA PLATAFORMA ARTIFICIAL!)
	_preview_jungle_root = Node3D.new()
	_preview_viewport.add_child(_preview_jungle_root)
	_build_ps1_jungle(_preview_jungle_root)

	# Pivot onde o kart fica montado diretamente na trilha da floresta
	_preview_pivot = Node3D.new()
	_preview_pivot.position = Vector3(0, 0.12, 0)
	_preview_viewport.add_child(_preview_pivot)

	# Seletor de Heróis na base
	var char_tabs_row := HBoxContainer.new()
	char_tabs_row.add_theme_constant_override("separation", 12)
	_center_heroes_view.add_child(char_tabs_row)

	_char_btn_boitata = _create_crash_button("🔥 COBRA BOITATÁ", false, false)
	_char_btn_boitata.custom_minimum_size = Vector2(0, 46)
	_char_btn_boitata.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_char_btn_boitata.pressed.connect(func():
		_select_character(CharacterDataScript.BOITATA)
		_show_heroes_tab()
	)
	char_tabs_row.add_child(_char_btn_boitata)

	_char_btn_et = _create_crash_button("🛸 ET CLÁSSICO", false, false)
	_char_btn_et.custom_minimum_size = Vector2(0, 46)
	_char_btn_et.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_char_btn_et.pressed.connect(func():
		_select_character(CharacterDataScript.ET_VARGINHA)
		_show_heroes_tab()
	)
	char_tabs_row.add_child(_char_btn_et)

	# --- ABA 2: PAINEL DE CONTROLES & CONFIGURAÇÕES (NO LUGAR DOS HERÓIS) ---
	_build_center_controls_view(_center_col)


## Trata o clique do botão direito e scroll para girar a câmera do cenário 3D
func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_is_orbiting = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_cam_dist = clampf(_cam_dist - 0.22, 1.2, 5.8)
			_update_preview_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_cam_dist = clampf(_cam_dist + 0.22, 1.2, 5.8)
			_update_preview_camera()
	elif event is InputEventMouseMotion and _is_orbiting:
		var mm := event as InputEventMouseMotion
		_cam_yaw -= mm.relative.x * 0.0075
		_cam_pitch = clampf(_cam_pitch - mm.relative.y * 0.0075, deg_to_rad(-12.0), deg_to_rad(65.0))
		_update_preview_camera()


func _update_preview_camera() -> void:
	if not _preview_camera or not _preview_camera.is_inside_tree():
		return
	var x: float = _cam_dist * sin(_cam_yaw) * cos(_cam_pitch)
	var y: float = _cam_target.y + _cam_dist * sin(_cam_pitch)
	var z: float = _cam_dist * cos(_cam_yaw) * cos(_cam_pitch)
	_preview_camera.look_at_from_position(Vector3(x, y, z), _cam_target, Vector3.UP)


## Constrói a aba de Controles com o mesmo fundo, madeira de Aku Aku e pergaminho do print
func _build_center_controls_view(parent: Control) -> void:
	_center_controls_view = VBoxContainer.new()
	_center_controls_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center_controls_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center_controls_view.add_theme_constant_override("separation", 0)
	_center_controls_view.visible = false
	parent.add_child(_center_controls_view)

	# 1. TOPO DE MADEIRA DO AKU AKU
	var wood_header := PanelContainer.new()
	wood_header.custom_minimum_size = Vector2(0, 54)
	var wsb := StyleBoxFlat.new()
	wsb.bg_color = Color(0.48, 0.28, 0.14)
	wsb.border_width_top = 3
	wsb.border_width_bottom = 3
	wsb.border_width_left = 3
	wsb.border_width_right = 3
	wsb.border_color = Color(0.32, 0.18, 0.08)
	wsb.set_corner_radius_all(6)
	wsb.set_content_margin_all(8)
	wood_header.add_theme_stylebox_override("panel", wsb)
	_center_controls_view.add_child(wood_header)

	var wood_row := HBoxContainer.new()
	wood_row.add_theme_constant_override("separation", 8)
	wood_row.alignment = BoxContainer.ALIGNMENT_CENTER
	wood_header.add_child(wood_row)

	var left_aku := Label.new()
	left_aku.text = "🔩 🎭🪶"
	left_aku.add_theme_font_size_override("font_size", 18)
	wood_row.add_child(left_aku)

	var wood_title := Label.new()
	wood_title.text = "CONFIGURAÇÕES & CONTROLES"
	wood_title.add_theme_font_size_override("font_size", 16)
	wood_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.15))
	wood_title.add_theme_constant_override("outline_size", 6)
	wood_title.add_theme_color_override("font_outline_color", Color(0.2, 0.08, 0.02))
	wood_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wood_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wood_row.add_child(wood_title)

	var right_feathers := Label.new()
	right_feathers.text = "🪶 🔩"
	right_feathers.add_theme_font_size_override("font_size", 18)
	wood_row.add_child(right_feathers)

	# 2. CORPO DO PERGAMINHO BEGE DESENROLADO
	var parchment_body := PanelContainer.new()
	parchment_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.96, 0.91, 0.82)
	psb.border_width_left = 3
	psb.border_width_right = 3
	psb.border_width_bottom = 4
	psb.border_color = Color(0.78, 0.68, 0.52)
	psb.set_corner_radius_all(4)
	psb.set_content_margin_all(14)
	parchment_body.add_theme_stylebox_override("panel", psb)
	_center_controls_view.add_child(parchment_body)

	var p_vbox := VBoxContainer.new()
	p_vbox.add_theme_constant_override("separation", 10)
	parchment_body.add_child(p_vbox)

	var scroll_sub := Label.new()
	scroll_sub.text = "Ajuste o som da mata amazônica, gráficos e domine os comandos do kart"
	scroll_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scroll_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroll_sub.add_theme_font_size_override("font_size", 12)
	scroll_sub.add_theme_color_override("font_color", Color(0.32, 0.22, 0.14))
	p_vbox.add_child(scroll_sub)

	# Fileira de Badges de Configurações
	var c_badges := HBoxContainer.new()
	c_badges.alignment = BoxContainer.ALIGNMENT_CENTER
	c_badges.add_theme_constant_override("separation", 6)
	p_vbox.add_child(c_badges)
	_build_badges_row(c_badges)

	# Área de Scroll interna
	var scroll_area := ScrollContainer.new()
	scroll_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_area.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p_vbox.add_child(scroll_area)

	var card_list := VBoxContainer.new()
	card_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_list.add_theme_constant_override("separation", 8)
	scroll_area.add_child(card_list)

	# --- CARD 1: VOLUME & TRILHA DA FLORESTA AMAZÔNICA ---
	var vol_card := _create_parchment_card(card_list, Color(0.2, 0.55, 0.3))
	var vol_vb := vol_card.get_child(0) as VBoxContainer

	var vol_title := Label.new()
	vol_title.text = "🎵 VOLUME GERAL & TRILHA AMAZÔNICA"
	vol_title.add_theme_font_size_override("font_size", 12)
	vol_title.add_theme_color_override("font_color", Color(0.12, 0.42, 0.2))
	vol_vb.add_child(vol_title)

	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 8)
	vol_vb.add_child(vol_row)

	var vol_ico_down := Label.new()
	vol_ico_down.text = "🔈"
	vol_ico_down.add_theme_font_size_override("font_size", 15)
	vol_row.add_child(vol_ico_down)

	_vol_slider = HSlider.new()
	_vol_slider.min_value = 0.0
	_vol_slider.max_value = 1.0
	_vol_slider.step = 0.01
	_vol_slider.value = 0.8
	_vol_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vol_slider.value_changed.connect(_on_volume_changed)
	vol_row.add_child(_vol_slider)

	var vol_ico_up := Label.new()
	vol_ico_up.text = "🔊"
	vol_ico_up.add_theme_font_size_override("font_size", 15)
	vol_row.add_child(vol_ico_up)

	_vol_lbl = Label.new()
	_vol_lbl.text = "80%"
	_vol_lbl.custom_minimum_size = Vector2(40, 0)
	_vol_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_vol_lbl.add_theme_font_size_override("font_size", 12)
	_vol_lbl.add_theme_color_override("font_color", Color(0.24, 0.18, 0.12))
	vol_row.add_child(_vol_lbl)

	var vol_desc := Label.new()
	vol_desc.text = "Ajusta o volume do tema amazônico (tambores, flauta indígena e pássaros) e dos rolamentos de aço."
	vol_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vol_desc.add_theme_font_size_override("font_size", 10)
	vol_desc.add_theme_color_override("font_color", Color(0.35, 0.26, 0.16))
	vol_vb.add_child(vol_desc)

	# --- CARD 2: RESOLUÇÃO E MODO DE TELA (JANELA OU TELA CHEIA) ---
	var video_card := _create_parchment_card(card_list, Color(0.18, 0.45, 0.75))
	var video_vb := video_card.get_child(0) as VBoxContainer

	var video_title := Label.new()
	video_title.text = "🖥️ MODO DE TELA & RESOLUÇÃO"
	video_title.add_theme_font_size_override("font_size", 12)
	video_title.add_theme_color_override("font_color", Color(0.12, 0.35, 0.65))
	video_vb.add_child(video_title)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	video_vb.add_child(mode_row)

	var mode_lbl := Label.new()
	mode_lbl.text = "Exibição:"
	mode_lbl.add_theme_font_size_override("font_size", 11)
	mode_lbl.add_theme_color_override("font_color", Color(0.24, 0.18, 0.12))
	mode_row.add_child(mode_lbl)

	_window_mode_option = OptionButton.new()
	_window_mode_option.add_item("Modo Janela (Windowed)", 0)
	_window_mode_option.add_item("Tela Cheia (Fullscreen)", 1)
	_window_mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_window_mode_option.item_selected.connect(_on_window_mode_selected)
	mode_row.add_child(_window_mode_option)

	var res_row := HBoxContainer.new()
	res_row.add_theme_constant_override("separation", 8)
	video_vb.add_child(res_row)

	var res_lbl := Label.new()
	res_lbl.text = "Resolução:"
	res_lbl.add_theme_font_size_override("font_size", 11)
	res_lbl.add_theme_color_override("font_color", Color(0.24, 0.18, 0.12))
	res_row.add_child(res_lbl)

	_res_option = OptionButton.new()
	_res_option.add_item("1920 × 1080 (Full HD 16:9)", 0)
	_res_option.add_item("1600 × 900 (HD+ 16:9)", 1)
	_res_option.add_item("1280 × 720 (HD Padrão)", 2)
	_res_option.add_item("1024 × 576 (Retrô 16:9)", 3)
	_res_option.add_item("800 × 600 (Retrô 4:3)", 4)
	_res_option.selected = 2
	_res_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_res_option.item_selected.connect(_on_resolution_selected)
	res_row.add_child(_res_option)

	var video_desc := Label.new()
	video_desc.text = "Alterne rapidamente entre modo janela e tela cheia e selecione a resolução desejada."
	video_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	video_desc.add_theme_font_size_override("font_size", 10)
	video_desc.add_theme_color_override("font_color", Color(0.35, 0.26, 0.16))
	video_vb.add_child(video_desc)

	# --- CARD 3: MAPA DE CONTROLES DO KART E CÂMERA ---
	var ctrl_card := _create_parchment_card(card_list, Color(0.72, 0.25, 0.15))
	var ctrl_vb := ctrl_card.get_child(0) as VBoxContainer

	var ctrl_title := Label.new()
	ctrl_title.text = "🎮 MAPA DE CONTROLES & CÂMERA 3D"
	ctrl_title.add_theme_font_size_override("font_size", 12)
	ctrl_title.add_theme_color_override("font_color", Color(0.68, 0.18, 0.1))
	ctrl_vb.add_child(ctrl_title)

	var ctrl_text := Label.new()
	ctrl_text.text = """• W / S ou Setas Cima / Baixo: Acelerar e Frear / Marcha Ré
• A / D ou Setas Esquerda / Direita: Esterçar caibro dianteiro
• Tecla [Q] ou Botão X (Controle): Disparar Poder de DANO
• Tecla [E] ou Botão Y (Controle): Ativar BARREIRA protetora
• Tecla [R]: Respawn imediato no topo da ladeira
• Tecla [Esc]: Abrir menu de pausa e voltar ao lobby
• 🖱️ Botão Direito do Mouse: Clique e arraste para GIRAR e olhar o cenário em volta!
• 🛞 Roda do Mouse: Zoom in / Zoom out da câmera do lobby"""
	ctrl_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctrl_text.add_theme_font_size_override("font_size", 10)
	ctrl_text.add_theme_color_override("font_color", Color(0.24, 0.18, 0.12))
	ctrl_vb.add_child(ctrl_text)

	# Ponta enrolada da base
	var roll_bottom := PanelContainer.new()
	roll_bottom.custom_minimum_size = Vector2(0, 10)
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0.82, 0.72, 0.58)
	rsb.set_corner_radius_all(5)
	roll_bottom.add_theme_stylebox_override("panel", rsb)
	_center_controls_view.add_child(roll_bottom)

	# Botão de voltar para seleção de heróis
	var back_btn := _create_crash_button("✦ VOLTAR PARA SELEÇÃO DE HERÓIS ✦", true, false)
	back_btn.custom_minimum_size = Vector2(0, 44)
	back_btn.pressed.connect(_show_heroes_tab)
	_center_controls_view.add_child(back_btn)


func _show_heroes_tab() -> void:
	if _center_heroes_view and _center_controls_view:
		_center_heroes_view.visible = true
		_center_controls_view.visible = false
	_apply_crash_button_style(_btn_heroes, true, false)
	_apply_crash_button_style(_btn_controls, false, false)
	_reload_preview_kart()
	set_status("Heróis: Boitatá & ET Clássico! Clique com o botão direito e arraste para olhar a selva.")


func _show_controls_tab() -> void:
	if _center_heroes_view and _center_controls_view:
		_center_heroes_view.visible = false
		_center_controls_view.visible = true
	_apply_crash_button_style(_btn_heroes, false, false)
	_apply_crash_button_style(_btn_controls, true, false)
	set_status("Aba de Controles & Configurações aberta no lugar dos heróis!")


func _on_volume_changed(val: float) -> void:
	var bus_idx := AudioServer.get_bus_index("Master")
	if bus_idx >= 0:
		if val <= 0.01:
			AudioServer.set_bus_mute(bus_idx, true)
		else:
			AudioServer.set_bus_mute(bus_idx, false)
			AudioServer.set_bus_volume_db(bus_idx, linear_to_db(val))
	if _vol_lbl:
		_vol_lbl.text = "%d%%" % int(round(val * 100.0))
	_save_settings()


func _on_window_mode_selected(index: int) -> void:
	if DisplayServer.get_name() != "headless":
		if index == 1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			if _res_option:
				var res_idx: int = _res_option.selected
				if res_idx >= 0 and res_idx < RESOLUTIONS.size():
					var res: Vector2i = RESOLUTIONS[res_idx]
					DisplayServer.window_set_size(res)
					var screen_size: Vector2i = DisplayServer.screen_get_size()
					DisplayServer.window_set_position((screen_size - res) / 2)
	_save_settings()


func _on_resolution_selected(index: int) -> void:
	if index < 0 or index >= RESOLUTIONS.size():
		return
	var res: Vector2i = RESOLUTIONS[index]
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(res)
		var is_fullscreen: bool = (DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
		if not is_fullscreen:
			var screen_size: Vector2i = DisplayServer.screen_get_size()
			DisplayServer.window_set_position((screen_size - res) / 2)
	_save_settings()


## Constrói o ambiente de Floresta estilo PS1 (Crash Bandicoot 1 / CTR)
func _build_ps1_jungle(parent: Node3D) -> void:
	# Chão de terra e grama da selva
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(20, 20)
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.14, 0.36, 0.16) # Verde musgo PS1
	ground_mat.roughness = 0.95
	var ground_inst := MeshInstance3D.new()
	ground_inst.mesh = ground_mesh
	ground_inst.position = Vector3(0, 0, 0)
	parent.add_child(ground_inst)

	# Trilha de terra batida sob o carrinho
	var path_mesh := PlaneMesh.new()
	path_mesh.size = Vector2(3.0, 16)
	var path_mat := StandardMaterial3D.new()
	path_mat.albedo_color = Color(0.42, 0.25, 0.14) # Terra avermelhada
	path_mat.roughness = 0.9
	var path_inst := MeshInstance3D.new()
	path_inst.mesh = path_mesh
	path_inst.position = Vector3(0, 0.01, 0)
	parent.add_child(path_inst)

	# Árvores tropicais low-poly estilo Crash 1 (troncos e copas cônicas poligonais)
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.44, 0.26, 0.12)
	trunk_mat.roughness = 0.85

	var leaf_mat_1 := StandardMaterial3D.new()
	leaf_mat_1.albedo_color = Color(0.14, 0.56, 0.22) # Verde vibrante de PS1
	leaf_mat_1.roughness = 0.8

	var leaf_mat_2 := StandardMaterial3D.new()
	leaf_mat_2.albedo_color = Color(0.24, 0.68, 0.26)

	var tree_positions = [
		Vector3(-2.8, 0, -2.2), Vector3(3.0, 0, -2.4),
		Vector3(-3.8, 0, 1.0), Vector3(3.6, 0, 1.2),
		Vector3(-2.2, 0, -4.8), Vector3(2.4, 0, -4.5),
		Vector3(-4.6, 0, -3.5), Vector3(4.4, 0, -3.8)
	]

	for tp in tree_positions:
		var tree := Node3D.new()
		tree.position = tp

		var tr_mesh := CylinderMesh.new()
		tr_mesh.top_radius = 0.18
		tr_mesh.bottom_radius = 0.40
		tr_mesh.height = 3.2
		tr_mesh.radial_segments = 6 # Low-poly característico de PS1!
		tr_mesh.material = trunk_mat
		var tr_inst := MeshInstance3D.new()
		tr_inst.mesh = tr_mesh
		tr_inst.position = Vector3(0, 1.6, 0)
		tree.add_child(tr_inst)

		for i in range(3):
			var leaf_mesh := CylinderMesh.new()
			leaf_mesh.top_radius = 0.05
			leaf_mesh.bottom_radius = 1.45 - i * 0.32
			leaf_mesh.height = 0.85
			leaf_mesh.radial_segments = 6 # 6 faces poligonais
			leaf_mesh.material = leaf_mat_1 if i % 2 == 0 else leaf_mat_2
			var leaf_inst := MeshInstance3D.new()
			leaf_inst.mesh = leaf_mesh
			leaf_inst.position = Vector3(0, 2.7 + i * 0.65, 0)
			tree.add_child(leaf_inst)

		parent.add_child(tree)

	# Samambaias e folhagens tropicais de selva
	var fern_mat := StandardMaterial3D.new()
	fern_mat.albedo_color = Color(0.2, 0.75, 0.3)
	fern_mat.roughness = 0.7
	for fx in [-1.6, 1.6, -2.2, 2.1]:
		for fz in [-0.8, 0.7, -1.8]:
			var fern := MeshInstance3D.new()
			var fm := BoxMesh.new()
			fm.size = Vector3(0.5, 0.3, 0.5)
			fern.mesh = fm
			fern.material_override = fern_mat
			fern.position = Vector3(fx + randf_range(-0.2, 0.2), 0.15, fz + randf_range(-0.2, 0.2))
			fern.rotation = Vector3(0, randf_range(-PI, PI), 0)
			parent.add_child(fern)

	# Vaga-lumes mágicos flutuantes dourados da floresta
	var firefly := CPUParticles3D.new()
	var ff_mat := StandardMaterial3D.new()
	ff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ff_mat.albedo_color = Color(1.0, 0.88, 0.25)
	var ff_mesh := SphereMesh.new()
	ff_mesh.radius = 0.035
	ff_mesh.height = 0.07
	ff_mesh.material = ff_mat
	firefly.mesh = ff_mesh
	firefly.amount = 28
	firefly.lifetime = 3.2
	firefly.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	firefly.emission_box_extents = Vector3(3.5, 2.2, 3.5)
	firefly.direction = Vector3(0, 1, 0)
	firefly.spread = 180.0
	firefly.initial_velocity_min = 0.1
	firefly.initial_velocity_max = 0.35
	firefly.gravity = Vector3(0, 0.04, 0)
	firefly.position = Vector3(0, 1.1, 0)
	parent.add_child(firefly)


# ================================================================= CAIXA DE TEXTO IDÊNTICA AO PRINT DO AKU AKU

func _build_right_column(parent: Control) -> void:
	_aku_panel = PanelContainer.new()
	_aku_panel.custom_minimum_size = Vector2(380, 0)
	_aku_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var root_sb := StyleBoxEmpty.new()
	_aku_panel.add_theme_stylebox_override("panel", root_sb)
	parent.add_child(_aku_panel)

	var scroll_root := VBoxContainer.new()
	scroll_root.add_theme_constant_override("separation", 0)
	_aku_panel.add_child(scroll_root)

	# 1. TOPO DE MADEIRA DO AKU AKU (com veios, parafusos e penas)
	var wood_header := PanelContainer.new()
	wood_header.custom_minimum_size = Vector2(0, 54)
	var wsb := StyleBoxFlat.new()
	wsb.bg_color = Color(0.48, 0.28, 0.14)
	wsb.border_width_top = 3
	wsb.border_width_bottom = 3
	wsb.border_width_left = 3
	wsb.border_width_right = 3
	wsb.border_color = Color(0.32, 0.18, 0.08)
	wsb.set_corner_radius_all(6)
	wsb.set_content_margin_all(8)
	wood_header.add_theme_stylebox_override("panel", wsb)
	scroll_root.add_child(wood_header)

	var wood_row := HBoxContainer.new()
	wood_row.add_theme_constant_override("separation", 8)
	wood_row.alignment = BoxContainer.ALIGNMENT_CENTER
	wood_header.add_child(wood_row)

	var left_aku := Label.new()
	left_aku.text = "🔩 🎭🪶"
	left_aku.add_theme_font_size_override("font_size", 18)
	wood_row.add_child(left_aku)

	_wood_title = Label.new()
	_wood_title.text = "PRIMEIROS PEDIDOS DO AKU"
	_wood_title.add_theme_font_size_override("font_size", 16)
	_wood_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.15))
	_wood_title.add_theme_constant_override("outline_size", 6)
	_wood_title.add_theme_color_override("font_outline_color", Color(0.2, 0.08, 0.02))
	_wood_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wood_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wood_row.add_child(_wood_title)

	var right_feathers := Label.new()
	right_feathers.text = "🪶 🔩"
	right_feathers.add_theme_font_size_override("font_size", 18)
	wood_row.add_child(right_feathers)

	# 2. CORPO DO PERGAMINHO DESENROLADO
	var parchment_body := PanelContainer.new()
	parchment_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.96, 0.91, 0.82)
	psb.border_width_left = 3
	psb.border_width_right = 3
	psb.border_width_bottom = 4
	psb.border_color = Color(0.78, 0.68, 0.52)
	psb.set_corner_radius_all(4)
	psb.set_content_margin_all(14)
	parchment_body.add_theme_stylebox_override("panel", psb)
	scroll_root.add_child(parchment_body)

	var p_vbox := VBoxContainer.new()
	p_vbox.add_theme_constant_override("separation", 8)
	parchment_body.add_child(p_vbox)

	_scroll_subtitle = Label.new()
	_scroll_subtitle.text = "Ganhe velocidade enquanto domina os poderes ancestrais"
	_scroll_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scroll_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scroll_subtitle.add_theme_font_size_override("font_size", 12)
	_scroll_subtitle.add_theme_color_override("font_color", Color(0.32, 0.22, 0.14))
	p_vbox.add_child(_scroll_subtitle)

	# 3. FILEIRA DE BADGES / EMBLEMAS
	_badges_row = HBoxContainer.new()
	_badges_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_badges_row.add_theme_constant_override("separation", 6)
	p_vbox.add_child(_badges_row)

	_build_badges_row(_badges_row)

	# 4. CARDS DAS HABILIDADES DETALHADAS DENTRO DO PERGAMINHO
	var scroll_detail := ScrollContainer.new()
	scroll_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_detail.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p_vbox.add_child(scroll_detail)

	var d_vbox := VBoxContainer.new()
	d_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d_vbox.add_theme_constant_override("separation", 6)
	scroll_detail.add_child(d_vbox)

	# Card 1: PASSIVA
	_passive_card = _create_parchment_card(d_vbox, Color(0.2, 0.55, 0.3))
	var p_card_vb := _passive_card.get_child(0) as VBoxContainer
	_passive_name = Label.new()
	_passive_name.add_theme_font_size_override("font_size", 12)
	_passive_name.add_theme_color_override("font_color", Color(0.12, 0.42, 0.2))
	p_card_vb.add_child(_passive_name)
	_passive_desc = Label.new()
	_passive_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_passive_desc.add_theme_font_size_override("font_size", 11)
	_passive_desc.add_theme_color_override("font_color", Color(0.24, 0.18, 0.12))
	p_card_vb.add_child(_passive_desc)

	# Card 2: HABILIDADE DE DANO [Q]
	_damage_card = _create_parchment_card(d_vbox, Color(0.72, 0.25, 0.15))
	var d_card_vb := _damage_card.get_child(0) as VBoxContainer
	_damage_name = Label.new()
	_damage_name.add_theme_font_size_override("font_size", 12)
	_damage_name.add_theme_color_override("font_color", Color(0.68, 0.18, 0.1))
	d_card_vb.add_child(_damage_name)
	_damage_meta = Label.new()
	_damage_meta.add_theme_font_size_override("font_size", 10)
	_damage_meta.add_theme_color_override("font_color", Color(0.55, 0.35, 0.1))
	d_card_vb.add_child(_damage_meta)
	_damage_desc = Label.new()
	_damage_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_damage_desc.add_theme_font_size_override("font_size", 11)
	_damage_desc.add_theme_color_override("font_color", Color(0.24, 0.18, 0.12))
	d_card_vb.add_child(_damage_desc)

	# Card 3: HABILIDADE DE BARREIRA [E]
	_barrier_card = _create_parchment_card(d_vbox, Color(0.18, 0.45, 0.75))
	var b_card_vb := _barrier_card.get_child(0) as VBoxContainer
	_barrier_name = Label.new()
	_barrier_name.add_theme_font_size_override("font_size", 12)
	_barrier_name.add_theme_color_override("font_color", Color(0.12, 0.35, 0.65))
	b_card_vb.add_child(_barrier_name)
	_barrier_meta = Label.new()
	_barrier_meta.add_theme_font_size_override("font_size", 10)
	_barrier_meta.add_theme_color_override("font_color", Color(0.18, 0.45, 0.65))
	b_card_vb.add_child(_barrier_meta)
	_barrier_desc = Label.new()
	_barrier_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_barrier_desc.add_theme_font_size_override("font_size", 11)
	_barrier_desc.add_theme_color_override("font_color", Color(0.24, 0.18, 0.12))
	b_card_vb.add_child(_barrier_desc)

	# 5. RODAPÉ DO PERGAMINHO
	var scroll_footer := HBoxContainer.new()
	scroll_footer.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll_footer.add_theme_constant_override("separation", 6)
	p_vbox.add_child(scroll_footer)

	var r2_badge := Label.new()
	r2_badge.text = "🎮 R2"
	r2_badge.add_theme_font_size_override("font_size", 11)
	r2_badge.add_theme_color_override("font_color", Color(0.42, 0.28, 0.16))
	scroll_footer.add_child(r2_badge)

	var r2_text := Label.new()
	r2_text.text = "Detalhes das Habilidades e Passivas"
	r2_text.add_theme_font_size_override("font_size", 11)
	r2_text.add_theme_color_override("font_color", Color(0.35, 0.24, 0.15))
	scroll_footer.add_child(r2_text)

	# Ponta enrolada da base
	var roll_bottom := PanelContainer.new()
	roll_bottom.custom_minimum_size = Vector2(0, 10)
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0.82, 0.72, 0.58)
	rsb.set_corner_radius_all(5)
	roll_bottom.add_theme_stylebox_override("panel", rsb)
	scroll_root.add_child(roll_bottom)

	# Botão de confirmação de seleção
	_confirm_btn = _create_crash_button("✓ CONFIRMAR SELEÇÃO", true, false)
	_confirm_btn.custom_minimum_size = Vector2(0, 42)
	_confirm_btn.pressed.connect(func(): _on_confirm_character())
	scroll_root.add_child(_confirm_btn)

	_update_character_ui()


## Constrói a fileira de 8 badges estilizados idêntica à do print
func _build_badges_row(parent: Control) -> void:
	var badge_data = [
		{"icon": "🔥", "bg": Color(0.45, 0.18, 0.65), "border": Color(1.0, 0.82, 0.2)}, # Roxo/Ouro
		{"icon": "💥", "bg": Color(0.65, 0.18, 0.18), "border": Color(1.0, 0.55, 0.2)}, # Fogo
		{"icon": "🛡️", "bg": Color(0.18, 0.35, 0.75), "border": Color(0.35, 0.8, 1.0)}, # Barreira
		{"icon": "⚡", "bg": Color(0.55, 0.15, 0.65), "border": Color(0.9, 0.4, 1.0)},  # Plasma
		{"icon": "🇧🇷", "bg": Color(0.12, 0.45, 0.22), "border": Color(1.0, 0.82, 0.15)}, # Brasil
		{"icon": "🛸", "bg": Color(0.15, 0.45, 0.65), "border": Color(0.3, 0.95, 0.8)},  # Alien
		{"icon": "⭐", "bg": Color(0.75, 0.55, 0.12), "border": Color(1.0, 0.9, 0.3)},   # XP
		{"icon": "🏁", "bg": Color(0.18, 0.22, 0.35), "border": Color(0.7, 0.8, 0.95)}   # Bandeira
	]

	for b in badge_data:
		var b_panel := PanelContainer.new()
		b_panel.custom_minimum_size = Vector2(34, 34)
		var b_sb := StyleBoxFlat.new()
		b_sb.bg_color = b["bg"]
		b_sb.border_color = b["border"]
		b_sb.border_width_left = 2
		b_sb.border_width_right = 2
		b_sb.border_width_top = 2
		b_sb.border_width_bottom = 2
		b_sb.set_corner_radius_all(7)
		b_sb.set_content_margin_all(2)
		b_panel.add_theme_stylebox_override("panel", b_sb)

		var l := Label.new()
		l.text = b["icon"]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 14)
		b_panel.add_child(l)
		parent.add_child(b_panel)


func _create_parchment_card(parent: Control, border_col: Color) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.92, 0.87, 0.76, 0.85) # Pergaminho suave
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	sb.border_width_left = 3
	sb.border_color = border_col
	pc.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	pc.add_child(vb)
	parent.add_child(pc)
	return pc


## Cria botões no estilo Crash Team Rumble
func _create_crash_button(btn_text: String, is_gold: bool = false, is_play_btn: bool = false) -> Button:
	var b := Button.new()
	b.text = btn_text
	b.custom_minimum_size = Vector2(230, 48)
	_apply_crash_button_style(b, is_gold, is_play_btn)
	return b


func _apply_crash_button_style(b: Button, is_gold: bool = false, is_play_btn: bool = false) -> void:
	var sb_normal := StyleBoxFlat.new()
	var sb_hover := StyleBoxFlat.new()
	var sb_pressed := StyleBoxFlat.new()

	sb_normal.set_corner_radius_all(8)
	sb_hover.set_corner_radius_all(8)
	sb_pressed.set_corner_radius_all(8)
	sb_normal.set_content_margin_all(6)
	sb_hover.set_content_margin_all(6)
	sb_pressed.set_content_margin_all(6)

	if is_play_btn:
		sb_normal.bg_color = Color(1.0, 0.78, 0.12)
		sb_normal.border_width_bottom = 5
		sb_normal.border_width_left = 3
		sb_normal.border_width_right = 3
		sb_normal.border_width_top = 3
		sb_normal.border_color = Color(0.12, 0.38, 0.85)

		sb_hover.bg_color = Color(1.0, 0.88, 0.25)
		sb_hover.border_width_bottom = 5
		sb_hover.border_width_left = 3
		sb_hover.border_width_right = 3
		sb_hover.border_width_top = 3
		sb_hover.border_color = Color(0.2, 0.55, 1.0)

		sb_pressed.bg_color = Color(0.9, 0.68, 0.08)
		sb_pressed.border_width_bottom = 2
		sb_pressed.border_color = Color(0.1, 0.3, 0.7)

		b.add_theme_color_override("font_color", Color(0.05, 0.15, 0.35))
		b.add_theme_color_override("font_hover_color", Color(0.02, 0.08, 0.22))
		b.add_theme_font_size_override("font_size", 22)
		b.add_theme_constant_override("outline_size", 4)
		b.add_theme_color_override("font_outline_color", Color(1.0, 0.92, 0.6))
	elif is_gold:
		sb_normal.bg_color = Color(0.16, 0.32, 0.6)
		sb_normal.border_width_bottom = 4
		sb_normal.border_width_left = 3
		sb_normal.border_width_right = 3
		sb_normal.border_width_top = 3
		sb_normal.border_color = Color(1.0, 0.82, 0.15)

		sb_hover.bg_color = Color(0.22, 0.42, 0.75)
		sb_hover.border_width_bottom = 4
		sb_hover.border_width_left = 3
		sb_hover.border_width_right = 3
		sb_hover.border_width_top = 3
		sb_hover.border_color = Color(1.0, 0.92, 0.35)

		sb_pressed.bg_color = Color(0.12, 0.25, 0.48)
		sb_pressed.border_width_bottom = 2
		sb_pressed.border_color = Color(0.8, 0.65, 0.1)

		b.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_constant_override("outline_size", 5)
		b.add_theme_color_override("font_outline_color", Color(0.04, 0.12, 0.28))
	else:
		sb_normal.bg_color = Color(0.1, 0.3, 0.62)
		sb_normal.border_width_bottom = 4
		sb_normal.border_width_left = 2
		sb_normal.border_width_right = 2
		sb_normal.border_width_top = 2
		sb_normal.border_color = Color(0.28, 0.6, 0.95)

		sb_hover.bg_color = Color(0.15, 0.4, 0.78)
		sb_hover.border_width_bottom = 4
		sb_hover.border_width_left = 2
		sb_hover.border_width_right = 2
		sb_hover.border_width_top = 2
		sb_hover.border_color = Color(0.45, 0.78, 1.0)

		sb_pressed.bg_color = Color(0.08, 0.22, 0.48)
		sb_pressed.border_width_bottom = 2
		sb_pressed.border_color = Color(0.2, 0.45, 0.75)

		b.add_theme_color_override("font_color", Color(1, 1, 1))
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_constant_override("outline_size", 5)
		b.add_theme_color_override("font_outline_color", Color(0.03, 0.1, 0.24))

	b.add_theme_stylebox_override("normal", sb_normal)
	b.add_theme_stylebox_override("hover", sb_hover)
	b.add_theme_stylebox_override("pressed", sb_pressed)


# ================================================================= MODAL DE MULTIPLAYER

func _build_multiplayer_dialog() -> void:
	_multiplayer_dialog = PanelContainer.new()
	_multiplayer_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_multiplayer_dialog.custom_minimum_size = Vector2(440, 0)
	_multiplayer_dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_multiplayer_dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	_multiplayer_dialog.visible = false

	var msb := StyleBoxFlat.new()
	msb.bg_color = Color(0.06, 0.12, 0.24, 0.96)
	msb.set_corner_radius_all(12)
	msb.set_content_margin_all(18)
	msb.border_width_left = 3
	msb.border_width_right = 3
	msb.border_width_top = 3
	msb.border_width_bottom = 3
	msb.border_color = Color(0.2, 0.85, 0.5)
	_multiplayer_dialog.add_theme_stylebox_override("panel", msb)
	add_child(_multiplayer_dialog)

	var mvb := VBoxContainer.new()
	mvb.add_theme_constant_override("separation", 10)
	_multiplayer_dialog.add_child(mvb)

	var m_title := Label.new()
	m_title.text = "SALA MULTIPLAYER ONLINE"
	m_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m_title.add_theme_font_size_override("font_size", 18)
	m_title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.15))
	mvb.add_child(m_title)

	mvb.add_child(_label("Nome do Piloto"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Piloto"
	_name_edit.text = "Piloto"
	_name_edit.max_length = 16
	_name_edit.text_changed.connect(func(t: String):
		if _top_name_edit:
			_top_name_edit.text = t
	)
	mvb.add_child(_name_edit)

	mvb.add_child(_label("Endereço do Servidor (Link Cloudflare ou IP)"))
	_addr_edit = LineEdit.new()
	_addr_edit.placeholder_text = "wss://xxxx.trycloudflare.com  ou  localhost"
	mvb.add_child(_addr_edit)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	mvb.add_child(btn_row)

	var join_btn := _create_crash_button("ENTRAR", false, false)
	join_btn.custom_minimum_size = Vector2(0, 40)
	join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_btn.pressed.connect(_on_join)
	btn_row.add_child(join_btn)

	var host_btn := _create_crash_button("HOSPEDAR", false, false)
	host_btn.custom_minimum_size = Vector2(0, 40)
	host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_btn.visible = not Net.is_web()
	host_btn.pressed.connect(_on_host)
	btn_row.add_child(host_btn)

	var close_btn := Button.new()
	close_btn.text = "Fechar"
	close_btn.custom_minimum_size = Vector2(0, 30)
	close_btn.pressed.connect(func(): _multiplayer_dialog.visible = false)
	mvb.add_child(close_btn)


# ================================================================= MENU DE PAUSA (IN-GAME)

func _build_pause_menu() -> void:
	_pause_menu = PanelContainer.new()
	_pause_menu.set_anchors_preset(Control.PRESET_CENTER)
	_pause_menu.custom_minimum_size = Vector2(360, 0)
	_pause_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pause_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_pause_menu.visible = false

	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.06, 0.1, 0.2, 0.94)
	psb.set_corner_radius_all(12)
	psb.set_content_margin_all(18)
	psb.border_width_top = 3
	psb.border_width_bottom = 3
	psb.border_color = Color(1.0, 0.82, 0.15)
	_pause_menu.add_theme_stylebox_override("panel", psb)
	add_child(_pause_menu)

	var pvb := VBoxContainer.new()
	pvb.add_theme_constant_override("separation", 10)
	_pause_menu.add_child(pvb)

	var p_title := Label.new()
	p_title.text = "JOGO PAUSADO"
	p_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p_title.add_theme_font_size_override("font_size", 22)
	p_title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.15))
	pvb.add_child(p_title)

	_resume_btn = _create_crash_button("CONTINUAR DESCIDA", true, false)
	_resume_btn.pressed.connect(_hide_pause)
	pvb.add_child(_resume_btn)

	_restart_btn = _create_crash_button("VOLTAR AO TOPO DA LADEIRA", false, false)
	_restart_btn.pressed.connect(_on_restart_top)
	pvb.add_child(_restart_btn)

	_leave_btn = _create_crash_button("VOLTAR AO LOBBY", false, false)
	_leave_btn.pressed.connect(func():
		_hide_pause()
		leave_requested.emit()
		show_menu("")
	)
	pvb.add_child(_leave_btn)


# ================================================================= HUD IN-GAME

func _build_hud() -> void:
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.visible = false
	add_child(_hud)

	_info = Label.new()
	_info.position = Vector2(16, 12)
	_info.add_theme_font_size_override("font_size", 14)
	_info.add_theme_constant_override("outline_size", 4)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_child(_info)

	_timer_lbl = Label.new()
	_timer_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_timer_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_timer_lbl.offset_top = 14
	_timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_lbl.add_theme_font_size_override("font_size", 22)
	_timer_lbl.add_theme_constant_override("outline_size", 6)
	_timer_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_child(_timer_lbl)

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

	_slope_lbl = Label.new()
	_slope_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_slope_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_slope_lbl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_slope_lbl.offset_bottom = -42
	_slope_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slope_lbl.add_theme_font_size_override("font_size", 26)
	_slope_lbl.add_theme_constant_override("outline_size", 7)
	_slope_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_child(_slope_lbl)

	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.offset_left = 16
	_hint.offset_bottom = -12
	_hint.text = "Esc: Menu · R: Respawn · [Q] Dano · [E] Barreira"
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.modulate = Color(1, 1, 1, 0.7)
	_hud.add_child(_hint)

	var skill_hud_panel := PanelContainer.new()
	skill_hud_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	skill_hud_panel.offset_left = 16
	skill_hud_panel.offset_bottom = -38
	skill_hud_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var sh_sb := StyleBoxFlat.new()
	sh_sb.bg_color = Color(0.06, 0.1, 0.2, 0.85)
	sh_sb.set_corner_radius_all(10)
	sh_sb.set_content_margin_all(10)
	sh_sb.border_width_left = 3
	sh_sb.border_color = Color(1.0, 0.82, 0.15)
	skill_hud_panel.add_theme_stylebox_override("panel", sh_sb)
	_hud.add_child(skill_hud_panel)

	var sh_vbox := VBoxContainer.new()
	sh_vbox.add_theme_constant_override("separation", 5)
	skill_hud_panel.add_child(sh_vbox)

	_hud_char_banner = Label.new()
	_hud_char_banner.text = "🔥 Boitatá"
	_hud_char_banner.add_theme_font_size_override("font_size", 15)
	sh_vbox.add_child(_hud_char_banner)

	_hud_passive_lbl = Label.new()
	_hud_passive_lbl.text = "Passiva: Fogo-Fátuo"
	_hud_passive_lbl.add_theme_font_size_override("font_size", 10)
	_hud_passive_lbl.modulate = Color(0.3, 0.9, 0.5)
	sh_vbox.add_child(_hud_passive_lbl)

	var h_skills := HBoxContainer.new()
	h_skills.add_theme_constant_override("separation", 8)
	sh_vbox.add_child(h_skills)

	# [Q] Dano
	_hud_damage_btn = PanelContainer.new()
	var d_sb := StyleBoxFlat.new()
	d_sb.bg_color = Color(0.35, 0.1, 0.1, 0.7)
	d_sb.set_corner_radius_all(6)
	d_sb.set_content_margin_all(6)
	_hud_damage_btn.add_theme_stylebox_override("panel", d_sb)
	var d_vb := VBoxContainer.new()
	d_vb.add_theme_constant_override("separation", 2)
	_hud_damage_btn.add_child(d_vb)
	_hud_damage_lbl = Label.new()
	_hud_damage_lbl.text = "💥 DANO [Q]"
	_hud_damage_lbl.add_theme_font_size_override("font_size", 11)
	_hud_damage_lbl.modulate = Color(1.0, 0.45, 0.3)
	d_vb.add_child(_hud_damage_lbl)
	_hud_damage_cd_lbl = Label.new()
	_hud_damage_cd_lbl.text = "PRONTA [Q]"
	_hud_damage_cd_lbl.add_theme_font_size_override("font_size", 12)
	_hud_damage_cd_lbl.modulate = Color(0.3, 1.0, 0.4)
	d_vb.add_child(_hud_damage_cd_lbl)
	h_skills.add_child(_hud_damage_btn)

	# [E] Barreira
	_hud_barrier_btn = PanelContainer.new()
	var b_sb := StyleBoxFlat.new()
	b_sb.bg_color = Color(0.1, 0.25, 0.45, 0.7)
	b_sb.set_corner_radius_all(6)
	b_sb.set_content_margin_all(6)
	_hud_barrier_btn.add_theme_stylebox_override("panel", b_sb)
	var b_vb := VBoxContainer.new()
	b_vb.add_theme_constant_override("separation", 2)
	_hud_barrier_btn.add_child(b_vb)
	_hud_barrier_lbl = Label.new()
	_hud_barrier_lbl.text = "🛡️ BARREIRA [E]"
	_hud_barrier_lbl.add_theme_font_size_override("font_size", 11)
	_hud_barrier_lbl.modulate = Color(0.35, 0.8, 1.0)
	b_vb.add_child(_hud_barrier_lbl)
	_hud_barrier_cd_lbl = Label.new()
	_hud_barrier_cd_lbl.text = "PRONTA [E]"
	_hud_barrier_cd_lbl.add_theme_font_size_override("font_size", 12)
	_hud_barrier_cd_lbl.modulate = Color(0.3, 1.0, 0.4)
	d_vb.add_child(_hud_barrier_cd_lbl)
	h_skills.add_child(_hud_barrier_btn)


# ================================================================= AÇÕES E SELEÇÃO DE HERÓIS

func _select_character(char_id: String) -> void:
	_selected_character_id = char_id
	Net.player_character = char_id
	_save_settings()
	_reload_preview_kart()
	_update_character_ui()


func _on_confirm_character() -> void:
	Net.player_character = _selected_character_id
	_save_settings()
	_update_character_ui()
	set_status("Herói %s pronto para rasgar as descidas!" % CharacterDataScript.get_character(_selected_character_id).name)


func _reload_preview_kart() -> void:
	if not _preview_pivot:
		return
	if is_instance_valid(_preview_kart):
		_preview_kart.queue_free()
		_preview_kart = null

	_preview_kart = KART_SCENE.instantiate()
	_preview_kart.is_preview = true
	_preview_kart.character_id = _selected_character_id
	_preview_kart.position = Vector3(0, 0, 0)
	_preview_pivot.add_child(_preview_kart)


func _update_character_ui() -> void:
	var cdata: Dictionary = CharacterDataScript.get_character(_selected_character_id)
	var is_boitata := (_selected_character_id == CharacterDataScript.BOITATA)

	if _char_btn_boitata and _char_btn_et:
		_char_btn_boitata.modulate = Color(1.2, 1.2, 1.2) if is_boitata else Color(0.75, 0.75, 0.75)
		_char_btn_et.modulate = Color(1.2, 1.2, 1.2) if not is_boitata else Color(0.75, 0.75, 0.75)

	# Atualiza o título na madeira do Aku Aku
	if _wood_title:
		_wood_title.text = "LENDAS & PODERES: %s" % cdata.name.to_upper()

	# Subtítulo no pergaminho
	if _scroll_subtitle:
		_scroll_subtitle.text = "%s — %s" % [cdata.title, cdata.lore_category]

	# Passiva no pergaminho
	if _passive_name:
		_passive_name.text = "%s %s: %s" % [cdata.passive.icon, cdata.passive.tag, cdata.passive.name]
		_passive_desc.text = "%s\n%s" % [cdata.passive.summary, cdata.passive.description]

	# Habilidade 1 (Dano) no pergaminho
	if _damage_name:
		var dam: Dictionary = cdata.ability_damage
		_damage_name.text = "%s %s" % [dam.icon, dam.name]
		_damage_meta.text = "%s  |  Tecla: [%s]  |  Recarga: %.0fs" % [dam.tag, dam.key_pc, dam.cooldown]
		_damage_desc.text = "%s\n%s" % [dam.summary, dam.description]

	# Habilidade 2 (Barreira) no pergaminho
	if _barrier_name:
		var bar: Dictionary = cdata.ability_barrier
		_barrier_name.text = "%s %s" % [bar.icon, bar.name]
		_barrier_meta.text = "%s  |  Tecla: [%s]  |  Recarga: %.0fs  |  Duração: %.0fs" % [bar.tag, bar.key_pc, bar.cooldown, bar.duration]
		_barrier_desc.text = "%s\n%s" % [bar.summary, bar.description]

	if _confirm_btn:
		_confirm_btn.text = "✓ %s CONFIRMADO!" % cdata.name.to_upper()


func _show_powers_focus() -> void:
	_show_heroes_tab()
	set_status("Confira as habilidades de Dano [Q] e Barreira [E] detalhadas no pergaminho à direita!")


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 12)
	l.modulate = Color(1, 1, 1, 0.75)
	return l


func _current_name() -> String:
	var n := ""
	if _top_name_edit and _top_name_edit.text.strip_edges() != "":
		n = _top_name_edit.text.strip_edges()
	elif _name_edit and _name_edit.text.strip_edges() != "":
		n = _name_edit.text.strip_edges()
	return n if n != "" else "Piloto"


func _on_join() -> void:
	_save_settings()
	_multiplayer_dialog.visible = false
	join_requested.emit(_addr_edit.text, _current_name())


func _on_host() -> void:
	_save_settings()
	_multiplayer_dialog.visible = false
	host_requested.emit(_current_name())


func _on_practice() -> void:
	_save_settings()
	practice_requested.emit(_current_name())


func _on_restart_top() -> void:
	for k in get_tree().get_nodes_in_group("local_kart"):
		k.restart_at_top()
	_hide_pause()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	var master_vol := 0.8
	var is_fullscreen := false
	var res_idx := 2 # 1280x720 padrão
	if cfg.load(SETTINGS_PATH) == OK:
		var pname: String = cfg.get_value("player", "name", "Piloto")
		if _name_edit:
			_name_edit.text = pname
		if _top_name_edit:
			_top_name_edit.text = pname
		if _addr_edit:
			_addr_edit.text = cfg.get_value("net", "address", "")
		_selected_character_id = cfg.get_value("player", "character", CharacterDataScript.BOITATA)
		master_vol = cfg.get_value("audio", "master_volume", 0.8)
		is_fullscreen = cfg.get_value("video", "fullscreen", false)
		res_idx = cfg.get_value("video", "resolution_index", 2)

	if _vol_slider:
		_vol_slider.value = master_vol
	_on_volume_changed(master_vol)

	if _window_mode_option:
		_window_mode_option.selected = 1 if is_fullscreen else 0
	if _res_option:
		_res_option.selected = clampi(res_idx, 0, RESOLUTIONS.size() - 1)

	if DisplayServer.get_name() != "headless":
		if is_fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			if res_idx >= 0 and res_idx < RESOLUTIONS.size():
				var res: Vector2i = RESOLUTIONS[res_idx]
				DisplayServer.window_set_size(res)

	Net.player_character = _selected_character_id
	_update_character_ui()
	_reload_preview_kart()
	var from_url := Net.server_from_page_url()
	if from_url != "" and _addr_edit:
		_addr_edit.text = from_url


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	var pname := _current_name()
	cfg.set_value("player", "name", pname)
	if _addr_edit:
		cfg.set_value("net", "address", _addr_edit.text)
	cfg.set_value("player", "character", _selected_character_id)
	if _vol_slider:
		cfg.set_value("audio", "master_volume", _vol_slider.value)
	if _window_mode_option:
		cfg.set_value("video", "fullscreen", _window_mode_option.selected == 1)
	if _res_option:
		cfg.set_value("video", "resolution_index", _res_option.selected)
	cfg.save(SETTINGS_PATH)
	Net.player_name = pname
	Net.player_character = _selected_character_id
