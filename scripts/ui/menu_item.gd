class_name MenuItem
extends Button
## Item de menu em "letra gorda".
##
## Usabilidade:
## - UM único destaque: passar o mouse = focar, então mouse, toque, teclado e controle
##   sempre mostram o mesmo item selecionado (nada de hover e foco brigando).
## - Seleção bem visível à distância do sofá: cor amarela + seta animada + item maior
##   (não depende só da cor).
## - Altura mínima generosa para o dedo no celular.
## - Pode virar uma "linha de opção" (< VALOR >) que troca com esquerda/direita ou toque.

signal value_changed(index: int)

var caption := ""
var font_px := 46
var values: PackedStringArray = []
var value_index := 0

var _t := 0.0
var _scale_tween: Tween


func _init(text_: String = "", size_px := 46) -> void:
	caption = text_
	font_px = size_px


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_theme_font_override("font", UIStyle.display_font())
	add_theme_font_size_override("font_size", font_px)
	add_theme_color_override("font_color", UIStyle.CREAM)
	for k in ["font_hover_color", "font_focus_color", "font_hover_pressed_color"]:
		add_theme_color_override(k, UIStyle.SUN)
	add_theme_color_override("font_pressed_color", UIStyle.ORANGE)
	add_theme_color_override("font_disabled_color", Color(UIStyle.CREAM, 0.35))
	add_theme_color_override("font_outline_color", UIStyle.INK)
	add_theme_constant_override("outline_size", int(font_px * 0.3))
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = font_px * 0.95 # espaço para a seta
	empty.content_margin_right = 16
	empty.content_margin_top = 2
	empty.content_margin_bottom = 2
	for s in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(s, empty)
	custom_minimum_size.y = maxf(font_px * 1.3, 52.0)
	_refresh_text()
	mouse_entered.connect(func() -> void:
		if not disabled:
			grab_focus())
	focus_entered.connect(_on_focus_changed.bind(true))
	focus_exited.connect(_on_focus_changed.bind(false))
	resized.connect(func() -> void: pivot_offset = Vector2(0.0, size.y * 0.5))


func set_values(vals: PackedStringArray, idx: int) -> void:
	values = vals
	value_index = clampi(idx, 0, maxi(vals.size() - 1, 0))
	_refresh_text()


func _refresh_text() -> void:
	if values.is_empty():
		text = caption
	else:
		text = "%s   < %s >" % [caption, values[value_index]]


func _cycle(dir: int) -> void:
	if values.is_empty():
		return
	value_index = wrapi(value_index + dir, 0, values.size())
	_refresh_text()
	_bump(1.18)
	value_changed.emit(value_index)


func _pressed() -> void:
	_cycle(1)


func _gui_input(event: InputEvent) -> void:
	if values.is_empty():
		return
	if event.is_action_pressed("ui_left"):
		_cycle(-1)
		accept_event()
	elif event.is_action_pressed("ui_right"):
		_cycle(1)
		accept_event()


## Entrada em cascata ao abrir a tela: o item "salta" para o lugar.
func pop_in(delay: float) -> void:
	modulate.a = 0.0
	scale = Vector2(0.55, 0.55)
	var fade := create_tween()
	fade.tween_interval(delay)
	fade.tween_property(self, "modulate:a", 1.0, 0.16)
	if _scale_tween:
		_scale_tween.kill()
	_scale_tween = create_tween()
	_scale_tween.tween_interval(delay)
	_scale_tween.tween_property(self, "scale", Vector2.ONE * _rest_scale(), 0.42) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _rest_scale() -> float:
	return 1.1 if has_focus() else 1.0


func _bump(peak: float) -> void:
	if _scale_tween:
		_scale_tween.kill()
	_scale_tween = create_tween()
	_scale_tween.tween_property(self, "scale", Vector2.ONE * peak, 0.08)
	_scale_tween.tween_property(self, "scale", Vector2.ONE * _rest_scale(), 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_focus_changed(focused: bool) -> void:
	_t = 0.0
	if focused:
		_bump(1.2)
	else:
		if _scale_tween:
			_scale_tween.kill()
		_scale_tween = create_tween()
		_scale_tween.tween_property(self, "scale", Vector2.ONE, 0.15)
	queue_redraw()


func _process(delta: float) -> void:
	if has_focus():
		_t += delta
		queue_redraw()


func _draw() -> void:
	if not has_focus() or disabled:
		return
	# Seta indicadora "quicando" para a direita
	var h := font_px * 0.46
	var x := font_px * 0.2 + sin(_t * 9.0) * font_px * 0.08
	var cy := size.y * 0.5
	var tri := PackedVector2Array([Vector2(x, cy - h * 0.6), Vector2(x + h, cy), Vector2(x, cy + h * 0.6)])
	var o := font_px * 0.09
	var outline := PackedVector2Array([Vector2(x - o, cy - h * 0.6 - o * 1.6), Vector2(x + h + o * 1.8, cy), Vector2(x - o, cy + h * 0.6 + o * 1.6)])
	draw_colored_polygon(PackedVector2Array([outline[0] + Vector2(0, 4), outline[1] + Vector2(0, 4), outline[2] + Vector2(0, 4)]), Color(UIStyle.INK, 0.55))
	draw_colored_polygon(outline, UIStyle.INK)
	draw_colored_polygon(tri, UIStyle.SUN)
