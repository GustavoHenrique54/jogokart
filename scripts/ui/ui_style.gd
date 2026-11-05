class_name UIStyle
extends RefCounted
## Paleta, fontes e helpers do visual "cartoon retrô de madeira" da interface.
##
## Direção de arte (identidade própria do Rolimã, inspirada em menus de plataforma/kart dos anos 90):
## - Letras GORDAS com contorno marrom-escuro grosso e sombra deslocada (lê bem sobre qualquer fundo).
## - Painéis como PLACAS DE MADEIRA pregadas (combina com o carrinho de rolimã e a selva).
## - Cores quentes e saturadas; amarelo = selecionado, creme = normal.
## - Os menus ficam por cima do mundo 3D vivo, sem "janelas de programa".

const FONT_DISPLAY_PATH := "res://Assets/fonts/LuckiestGuy-Regular.ttf"
const FONT_BODY_PATH := "res://Assets/fonts/Nunito-Variable.ttf"

const INK := Color("2a1506") ## contorno "de desenho animado"
const CREAM := Color("fff4d8")
const SUN := Color("ffd23a") ## destaque / item selecionado
const ORANGE := Color("ff8f1f")
const LEAF := Color("63c94b")
const LEAF_DARK := Color("2f8a2a")
const BERRY := Color("ec4a3c")
const SKY := Color("3fc6dd")
const WOOD := Color("b8692f")
const WOOD_ALT := Color("a85d28")
const WOOD_LIGHT := Color("dc904f")
const PAPER := Color("fbe8c0")

static var _display: Font
static var _body: Font


static func display_font() -> Font:
	if _display == null:
		var base := _try_load(FONT_DISPLAY_PATH)
		if base == null:
			_display = body_font()
		else:
			var fv := FontVariation.new()
			fv.base_font = base
			var fb: Array[Font] = [body_font()]
			fv.fallbacks = fb
			_display = fv
	return _display


static func body_font() -> Font:
	if _body == null:
		var base := _try_load(FONT_BODY_PATH)
		if base == null:
			_body = ThemeDB.fallback_font
		else:
			var fv := FontVariation.new()
			fv.base_font = base
			var ts := TextServerManager.get_primary_interface()
			fv.variation_opentype = {ts.name_to_tag("wght"): 850}
			_body = fv
	return _body


static func _try_load(path: String) -> Font:
	if ResourceLoader.exists(path):
		return load(path) as Font
	return null


## Label com letra gorda, contorno grosso e sombra (o "carimbo" visual do jogo).
static func label(text: String, size := 28, color := CREAM, display := true) -> Label:
	var l := Label.new()
	l.text = text
	style_label(l, size, color, display)
	return l


static func style_label(l: Label, size: int, color: Color, display := true) -> void:
	var outline := maxi(4, int(size * (0.26 if display else 0.18)))
	l.add_theme_font_override("font", display_font() if display else body_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_shadow_color", Color(INK, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", maxi(2, int(size / 11.0)))
	l.add_theme_constant_override("shadow_outline_size", outline)


## Label de texto corrido (escuro, sem contorno) para usar em cima do "papel".
static func ink_label(text: String, size := 22) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", body_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", INK)
	return l


static func wood_box(planks := 4, nails := true) -> CartoonBox:
	var b := CartoonBox.new()
	b.fill = WOOD
	b.fill_alt = WOOD_ALT
	b.planks = planks
	b.nails = nails
	b.corner_radius = 18.0
	b.outline_width = 6.0
	b.set_content_margin_all(30)
	return b


static func paper_box(radius := 12.0) -> CartoonBox:
	var b := CartoonBox.new()
	b.fill = PAPER
	b.fill_alt = PAPER
	b.highlight = Color(1, 1, 1, 0.35)
	b.corner_radius = radius
	b.outline_width = 4.0
	b.shadow_offset = Vector2(0, 4)
	b.set_content_margin_all(12)
	return b


static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 22

	# Campo de texto = tira de papel com contorno; foco = contorno laranja grosso.
	var le := paper_box(12.0)
	le.content_margin_left = 16
	le.content_margin_right = 16
	var le_focus := CartoonBox.new()
	le_focus.draw_fill = false
	le_focus.outline_color = ORANGE
	le_focus.outline_width = 6.0
	le_focus.corner_radius = 12.0
	le_focus.shadow_offset = Vector2.ZERO
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le_focus)
	t.set_stylebox("read_only", "LineEdit", le)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(INK, 0.4))
	t.set_color("caret_color", "LineEdit", INK)
	t.set_color("selection_color", "LineEdit", Color(ORANGE, 0.45))
	t.set_font_size("font_size", "LineEdit", 26)
	t.set_constant("caret_width", "LineEdit", 3)
	return t
