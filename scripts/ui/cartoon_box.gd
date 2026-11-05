class_name CartoonBox
extends StyleBox
## StyleBox desenhado à mão: contorno grosso "de desenho animado", sombra deslocada e,
## opcionalmente, tábuas de madeira com veios e pregos. É a base de todos os painéis do jogo.

@export var fill := Color("b8692f")
@export var fill_alt := Color("a85d28")
@export var highlight := Color(1, 1, 1, 0.16)
@export var outline_color := Color("2a1506")
@export var outline_width := 5.0
@export var corner_radius := 16.0
@export var shadow_color := Color(0, 0, 0, 0.35)
@export var shadow_offset := Vector2(0, 7)
@export var draw_fill := true ## false = só o contorno (usado como indicador de foco)
@export var planks := 0 ## número de tábuas horizontais (0 = superfície lisa)
@export var nails := false


func _draw(ci: RID, rect: Rect2) -> void:
	if not draw_fill:
		var ring := rounded_points(rect.grow(outline_width * 0.5), corner_radius + outline_width * 0.5)
		ring.append(ring[0])
		RenderingServer.canvas_item_add_polyline(ci, ring, PackedColorArray([outline_color]), outline_width, true)
		return

	if shadow_color.a > 0.0 and shadow_offset != Vector2.ZERO:
		_poly(ci, rounded_points(Rect2(rect.position + shadow_offset, rect.size), corner_radius), shadow_color)
	_poly(ci, rounded_points(rect, corner_radius), outline_color)

	var inner := rect.grow(-outline_width)
	var ir := maxf(corner_radius - outline_width, 2.0)
	_poly(ci, rounded_points(inner, ir), fill)

	if planks > 1:
		var h := inner.size.y / float(planks)
		var seam := Color(outline_color, 0.5)
		var grain := Color(outline_color, 0.16)
		for i in planks:
			var y0 := inner.position.y + h * i
			var touches_corner := i == 0 or i == planks - 1
			var inset := ir if touches_corner else 0.0
			if i % 2 == 1:
				RenderingServer.canvas_item_add_rect(ci, Rect2(inner.position.x + inset, y0, inner.size.x - inset * 2.0, h), fill_alt)
			# veios da madeira (posições fixas por tábua, sem "piscar" entre frames)
			for g in 2:
				var fx := fmod(0.17 + i * 0.37 + g * 0.43, 0.8) + 0.06
				var gx := inner.position.x + inner.size.x * fx
				var gy := y0 + h * (0.35 + 0.3 * g)
				var gl := clampf(inner.size.x * 0.12, 18.0, 70.0)
				RenderingServer.canvas_item_add_line(ci, Vector2(gx, gy), Vector2(gx + gl, gy), grain, 2.0, true)
			if i > 0:
				RenderingServer.canvas_item_add_line(ci, Vector2(inner.position.x + 2.0, y0), Vector2(inner.end.x - 2.0, y0), seam, 3.0, true)

	# brilho na borda de cima (volume)
	var hl_h := maxf(3.0, outline_width * 0.7)
	RenderingServer.canvas_item_add_rect(ci, Rect2(inner.position.x + ir * 0.7, inner.position.y + 3.0, inner.size.x - ir * 1.4, hl_h), highlight)

	if nails:
		var off := clampf(ir * 0.75, 10.0, 18.0)
		for p in [inner.position + Vector2(off, off), Vector2(inner.end.x - off, inner.position.y + off),
				Vector2(inner.position.x + off, inner.end.y - off), inner.end - Vector2(off, off)]:
			RenderingServer.canvas_item_add_circle(ci, p, 5.5, outline_color)
			RenderingServer.canvas_item_add_circle(ci, p + Vector2(-1.2, -1.2), 2.0, Color(1, 1, 1, 0.45))


static func _poly(ci: RID, pts: PackedVector2Array, color: Color) -> void:
	RenderingServer.canvas_item_add_polygon(ci, pts, PackedColorArray([color]))


## Pontos de um retângulo arredondado (sentido horário em coordenadas de tela).
static func rounded_points(rect: Rect2, radius: float, seg := 6) -> PackedVector2Array:
	var r := clampf(radius, 1.0, minf(rect.size.x, rect.size.y) * 0.5 - 0.01)
	var pts := PackedVector2Array()
	if r <= 1.0:
		pts.append_array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
		return pts
	var centers: Array[Vector2] = [
		Vector2(rect.end.x - r, rect.position.y + r),
		Vector2(rect.end.x - r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.position.y + r),
	]
	for c in 4:
		var a0 := -PI * 0.5 + PI * 0.5 * c
		for s in seg + 1:
			var a := a0 + PI * 0.5 * float(s) / float(seg)
			pts.append(centers[c] + Vector2(cos(a), sin(a)) * r)
	return pts
