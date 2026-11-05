class_name TouchControls
extends Control
## Controles de toque para celular/tablet, no padrão dos jogos de corrida mobile:
##
## - Metade ESQUERDA da tela = "volante" flutuante: o analógico nasce onde o polegar encosta
##   (não precisa mirar num botão pequeno) e só lê o eixo horizontal. Se o dedo passar do raio,
##   a base acompanha, então nunca "trava" no limite.
## - DIREITA = botões grandes na zona natural do polegar (EMPURRA / FREIO / PULO). A área de toque
##   é maior que o desenho, e o botão continua pressionado mesmo se o dedo escorregar para fora.
## - "Empurrar sozinho" (padrão no toque): o carrinho embala sozinho e o jogador só precisa
##   virar e frear — joga confortável com dois polegares.
## - O botão de reposicionar fica pequeno e longe (perto da pausa) para não ser tocado sem querer.
## - Os toques viram ações do InputMap (Input.action_press), então o kart não sabe de onde veio
##   o comando: teclado, controle e toque usam exatamente a mesma física.

const STICK_RADIUS := 96.0
const DEADZONE := 0.08

var active := false:
	set(v):
		if active == v:
			return
		active = v
		visible = v
		queue_redraw()
		if not v:
			_release_all()

var kart: Kart ## kart local (para mostrar a recarga das habilidades)

var _buttons: Array[Dictionary] = []
var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _steer := 0.0
var _ghost_center := Vector2.ZERO
var _press_anim := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_buttons = [
		{"action": &"accelerate", "label": "EMPURRA", "color": UIStyle.LEAF},
		{"action": &"brake", "label": "FREIO", "color": UIStyle.BERRY},
		{"action": &"drift", "label": "PULO", "color": UIStyle.SUN},
		{"action": &"ability_damage", "label": "ATAQUE", "color": UIStyle.ORANGE, "cooldown": "damage"},
		{"action": &"ability_barrier", "label": "ESCUDO", "color": Color("9a6cff"), "cooldown": "barrier"},
		{"action": &"respawn", "label": "", "color": UIStyle.SKY, "icon": "respawn"},
	]
	for b in _buttons:
		b["touch"] = -1
		b["center"] = Vector2.ZERO
		b["radius"] = 50.0
		b["shown"] = true
	resized.connect(_layout)
	Settings.changed.connect(_layout)
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all()


func _layout() -> void:
	var s := Settings.touch_scale
	var m := 30.0 * s
	var br := Vector2(size.x - m, size.y - m)
	var auto := Settings.auto_push
	var push := _btn(&"accelerate")
	var brake := _btn(&"brake")
	# Botão principal no canto (o mais usado fica onde o polegar descansa);
	# os secundários formam um arco em volta dele, todos alcançáveis sem esticar o dedo.
	var main_c := br - Vector2(112, 112) * s
	var main_btn := brake if auto else push
	push["shown"] = not auto
	main_btn["center"] = main_c
	main_btn["radius"] = 86.0 * s
	var arc: Array[StringName] = [&"drift", &"ability_barrier", &"ability_damage"]
	var angles: Array[float] = [186.0, 229.0, 272.0]
	var arc_r := 192.0
	if not auto:
		arc = [&"brake", &"drift", &"ability_barrier", &"ability_damage"]
		angles = [180.0, 214.0, 248.0, 282.0]
		arc_r = 208.0
	for i in arc.size():
		var b := _btn(arc[i])
		var a := deg_to_rad(angles[i])
		b["center"] = main_c + Vector2(cos(a), sin(a)) * arc_r * s
		b["radius"] = (62.0 if arc[i] == &"brake" or arc[i] == &"drift" else 54.0) * s
	var resp := _btn(&"respawn")
	resp["center"] = Vector2(size.x - m - 44.0 * s, 178.0 * s)
	resp["radius"] = 40.0 * s
	_ghost_center = Vector2(m + 150.0 * s, size.y - m - 140.0 * s)
	queue_redraw()


func _btn(action: StringName) -> Dictionary:
	for b in _buttons:
		if b["action"] == action:
			return b
	return {}


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventScreenTouch:
		var p: Vector2 = (make_input_local(event) as InputEventScreenTouch).position
		if event.pressed:
			for b in _buttons:
				if b["shown"] and int(b["touch"]) == -1 and p.distance_to(b["center"]) <= float(b["radius"]) * 1.3:
					b["touch"] = event.index
					Input.action_press(b["action"])
					queue_redraw()
					get_viewport().set_input_as_handled()
					return
			if _stick_touch == -1 and p.x < size.x * 0.5 and p.y > size.y * 0.22:
				_stick_touch = event.index
				_stick_origin = _clamp_origin(p)
				_stick_pos = p
				_update_steer()
				get_viewport().set_input_as_handled()
		else:
			if event.index == _stick_touch:
				_stick_touch = -1
				_set_steer(0.0)
				queue_redraw()
			for b in _buttons:
				if int(b["touch"]) == event.index:
					b["touch"] = -1
					Input.action_release(b["action"])
					queue_redraw()
	elif event is InputEventScreenDrag and event.index == _stick_touch:
		_stick_pos = (make_input_local(event) as InputEventScreenDrag).position
		_update_steer()
		get_viewport().set_input_as_handled()


func _clamp_origin(p: Vector2) -> Vector2:
	var r := STICK_RADIUS * Settings.touch_scale
	return Vector2(clampf(p.x, r + 10.0, size.x * 0.5 - r * 0.5), clampf(p.y, r + 10.0, size.y - r * 0.6))


func _update_steer() -> void:
	var r := STICK_RADIUS * Settings.touch_scale
	var dx := _stick_pos.x - _stick_origin.x
	# Base flutuante: se o dedo passar do raio, a base vem junto.
	if absf(dx) > r:
		_stick_origin.x += dx - signf(dx) * r
		dx = signf(dx) * r
	var v := dx / r
	var mag := absf(v)
	var out := 0.0 if mag < DEADZONE else signf(v) * pow((mag - DEADZONE) / (1.0 - DEADZONE), 1.25)
	_set_steer(out)
	queue_redraw()


func _set_steer(v: float) -> void:
	_steer = v
	if v < 0.0:
		Input.action_press(&"steer_left", -v)
		Input.action_release(&"steer_right")
	elif v > 0.0:
		Input.action_press(&"steer_right", v)
		Input.action_release(&"steer_left")
	else:
		Input.action_release(&"steer_left")
		Input.action_release(&"steer_right")


func _release_all() -> void:
	_stick_touch = -1
	_steer = 0.0
	for a in [&"steer_left", &"steer_right", &"accelerate", &"brake", &"drift", &"respawn", &"ability_damage", &"ability_barrier"]:
		Input.action_release(a)
	for b in _buttons:
		b["touch"] = -1
	queue_redraw()


func _process(_delta: float) -> void:
	if not active:
		return
	queue_redraw()
	# Empurrar sozinho: embala enquanto o freio não estiver apertado.
	if Settings.auto_push:
		if int(_btn(&"brake")["touch"]) == -1:
			Input.action_press(&"accelerate")
		else:
			Input.action_release(&"accelerate")


# ----------------------------------------------------------------- desenho

func _draw() -> void:
	var s := Settings.touch_scale
	var font := UIStyle.display_font()
	var r := STICK_RADIUS * s

	# Volante (fantasma quando não está sendo usado, para ensinar onde tocar)
	var holding := _stick_touch != -1
	var origin := _stick_origin if holding else _ghost_center
	var a := 0.95 if holding else 0.45
	draw_circle(origin, r, Color(UIStyle.INK, 0.28 * a))
	draw_arc(origin, r, 0.0, TAU, 48, Color(UIStyle.CREAM, 0.75 * a), 5.0 * s, true)
	for dir: float in [-1.0, 1.0]:
		var tip := origin + Vector2(dir * (r - 16.0 * s), 0.0)
		var lit := (_steer * dir) > 0.05
		var c := UIStyle.SUN if lit else Color(UIStyle.CREAM, 0.8 * a)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-dir * 22.0, -18.0) * s, tip + Vector2(-dir * 22.0, 18.0) * s]), c)
	var knob := origin + Vector2(_steer_visual() * r * 0.62, 0.0)
	draw_circle(knob + Vector2(0, 5) * s, 42.0 * s, Color(0, 0, 0, 0.3 * a))
	draw_circle(knob, 42.0 * s, Color(UIStyle.INK, a))
	draw_circle(knob, 36.0 * s, Color(UIStyle.CREAM, a))
	if not holding:
		_text(font, "ARRASTE", origin + Vector2(0, r + 30.0 * s), int(22 * s), Color(UIStyle.CREAM, 0.8))

	for b in _buttons:
		if not b["shown"]:
			continue
		var pressed := int(b["touch"]) != -1
		var c: Vector2 = b["center"]
		var rad: float = float(b["radius"]) * (0.92 if pressed else 1.0)
		var col: Color = b["color"]
		if pressed:
			col = col.lightened(0.25)
		var fill_a := 0.92 if pressed else 0.78
		if not pressed:
			draw_circle(c + Vector2(0, 7) * s, rad, Color(0, 0, 0, 0.3))
		draw_circle(c, rad, Color(UIStyle.INK, 0.9))
		draw_circle(c, rad - 6.0 * s, Color(col, fill_a))
		draw_circle(c + Vector2(0, -rad * 0.38), rad * 0.42, Color(1, 1, 1, 0.16))
		var cd_kind: String = b.get("cooldown", "")
		if cd_kind != "" and kart:
			var left := kart.damage_cooldown if cd_kind == "damage" else kart.barrier_cooldown
			var total := kart.damage_max_cooldown if cd_kind == "damage" else kart.barrier_max_cooldown
			if cd_kind == "barrier" and kart.is_barrier_active():
				draw_arc(c, rad + 4.0 * s, 0.0, TAU, 40, UIStyle.SKY, 6.0 * s, true)
			elif left > 0.0:
				# Recarga: "pizza" escura que vai sumindo + segundos restantes
				var frac := clampf(left / maxf(total, 0.01), 0.0, 1.0)
				var pts := PackedVector2Array([c])
				var steps := 28
				for k in steps + 1:
					var ang := -PI * 0.5 + TAU * frac * float(k) / float(steps)
					pts.append(c + Vector2(cos(ang), sin(ang)) * (rad - 6.0 * s))
				if pts.size() >= 3:
					draw_colored_polygon(pts, Color(UIStyle.INK, 0.62))
				_text(font, str(ceili(left)), c, int(rad * 0.62), UIStyle.CREAM)
				continue
		if b.get("icon", "") == "respawn":
			draw_arc(c, rad * 0.42, deg_to_rad(-60), deg_to_rad(220), 20, UIStyle.INK, 9.0 * s, true)
			draw_arc(c, rad * 0.42, deg_to_rad(-60), deg_to_rad(220), 20, UIStyle.CREAM, 4.5 * s, true)
			var tip := c + Vector2(cos(deg_to_rad(-60)), sin(deg_to_rad(-60))) * rad * 0.42
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-10, -6) * s, tip + Vector2(10, -2) * s, tip + Vector2(-2, 12) * s]), UIStyle.CREAM)
		else:
			_text(font, b["label"], c, int(rad * 0.36), UIStyle.CREAM)


func _steer_visual() -> float:
	if _stick_touch == -1:
		return 0.0
	return clampf((_stick_pos.x - _stick_origin.x) / (STICK_RADIUS * Settings.touch_scale), -1.0, 1.0)


func _text(font: Font, t: String, center: Vector2, px: int, color: Color) -> void:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var pos := Vector2(center.x - w * 0.5, center.y + px * 0.36)
	draw_string_outline(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, maxi(6, int(px * 0.35)), UIStyle.INK)
	draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
