class_name PromptBar
extends HBoxContainer
## Barra de dicas de botão no rodapé (ex.: [A] SELECIONAR  [B] VOLTAR).
## O ícone acompanha o último dispositivo usado (teclado, controle ou toque), e cada dica
## também é clicável/tocável — quem está no mouse ou no celular não fica sem "voltar".

signal prompt_pressed(action: StringName)

var _entries: Array = [] ## [[action, text], ...]


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	alignment = BoxContainer.ALIGNMENT_END
	GameInput.device_changed.connect(func(_d: int) -> void: _rebuild())


func set_prompts(entries: Array) -> void:
	_entries = entries
	_rebuild()


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	for e in _entries:
		var action: StringName = e[0]
		# No toque, "selecionar" é tocar direto no item: só mostramos o VOLTAR.
		if GameInput.device == GameInput.Device.TOUCH and action == &"ui_accept":
			continue
		add_child(_make_pill(action, e[1]))


func _make_pill(action: StringName, text: String) -> Control:
	var pill := PanelContainer.new()
	var box := UIStyle.paper_box(26.0)
	box.content_margin_left = 10
	box.content_margin_right = 20
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	pill.add_theme_stylebox_override("panel", box)
	pill.mouse_filter = Control.MOUSE_FILTER_STOP
	pill.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(row)
	var glyph := PromptGlyph.new()
	glyph.action = action
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(glyph)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UIStyle.display_font())
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", UIStyle.INK)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	pill.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			prompt_pressed.emit(action)
			pill.accept_event())
	pill.mouse_entered.connect(func() -> void: pill.modulate = Color(1.08, 1.05, 0.9))
	pill.mouse_exited.connect(func() -> void: pill.modulate = Color.WHITE)
	return pill


## Ícone do botão desenhado à mão (círculo colorido do controle, tecla do teclado ou seta).
class PromptGlyph:
	extends Control

	var action: StringName = &"ui_accept"

	func _ready() -> void:
		custom_minimum_size = _glyph_size()

	func _glyph_size() -> Vector2:
		match GameInput.device:
			GameInput.Device.KEYBOARD:
				return Vector2(78 if action == &"ui_accept" else 58, 38)
			_:
				return Vector2(38, 38)

	func _draw() -> void:
		var font := UIStyle.display_font()
		var r := Rect2(Vector2.ZERO, size)
		match GameInput.device:
			GameInput.Device.GAMEPAD:
				var c := UIStyle.LEAF if action == &"ui_accept" else UIStyle.BERRY
				var center := size * 0.5
				draw_circle(center + Vector2(0, 3), 18.0, Color(UIStyle.INK, 0.4))
				draw_circle(center, 18.0, UIStyle.INK)
				draw_circle(center, 14.5, c)
				var t := "A" if action == &"ui_accept" else "B"
				_centered_text(font, t, center, 22, UIStyle.CREAM)
			GameInput.Device.KEYBOARD:
				var key := r.grow(-1)
				draw_colored_polygon(CartoonBox.rounded_points(Rect2(key.position + Vector2(0, 4), key.size), 8.0), UIStyle.INK)
				draw_colored_polygon(CartoonBox.rounded_points(key, 8.0), UIStyle.INK)
				draw_colored_polygon(CartoonBox.rounded_points(key.grow(-3), 6.0), UIStyle.CREAM)
				var t := "ENTER" if action == &"ui_accept" else "ESC"
				_centered_text(font, t, size * 0.5, 18, UIStyle.INK, false)
			_:
				var center := size * 0.5
				draw_circle(center, 18.0, UIStyle.INK)
				draw_circle(center, 14.5, UIStyle.ORANGE)
				var tri := PackedVector2Array([center + Vector2(5, -8), center + Vector2(-7, 0), center + Vector2(5, 8)])
				draw_colored_polygon(tri, UIStyle.CREAM)

	func _centered_text(font: Font, t: String, center: Vector2, px: int, color: Color, outline := true) -> void:
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var pos := Vector2(center.x - w * 0.5, center.y + px * 0.36)
		if outline:
			draw_string_outline(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 6, UIStyle.INK)
		draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
