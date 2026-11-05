@tool
extends Node3D
## Pista de descida de morro (Touge / Ladeira de Rolimã + Pumptrack) — OTIMIZADA PARA O VIEWPORT 3D!
##
## Por que agora roda liso no Editor 3D:
## 1. No Editor (`Engine.is_editor_hint()`), NÃO criamos `ConcavePolygonShape3D` (colisão trimesh),
##    porque o Godot desenha o gizmo de centenas de milhares de linhas de colisão no Viewport 3D,
##    o que travava a câmera! A colisão só é gerada quando o jogo roda (F5).
## 2. No Editor usamos resolução leve (`editor_preview_step = 7.0` e `editor_cross_slices = 6`)
##    e 1 única MeshInstance3D sem sombra projetada (`SHADOW_CASTING_SETTING_OFF`).
## 3. As árvores do fundo usam `MultiMeshInstance3D` (1 único draw call para todas as árvores)
##    em vez de centenas de nós individuais na árvore de cena.
## 4. Enquanto você arrasta um ponto da curva ou uma TrackZone, há um debounce de 0.15s para
##    não reconstruir a malha 60 vezes por segundo.

@export_group("Reconstruir / Exportar")
@export_tool_button("Reconstruir Malha da Pista Agora") var btn_rebuild := rebuild_track
@export_tool_button("Resetar Curva Padrão no TrackPath") var btn_reset_curve := reset_default_curve

@export_group("Performance no Editor 3D")
@export var editor_fast_mode := false: ## Desligado por padrão: exibe a pista com qualidade visual máxima no Viewport 3D!
	set(v):
		editor_fast_mode = v
		_apply_editor_perf_settings()
		_queue_rebuild()
@export var show_trees_in_editor := true:
	set(v):
		show_trees_in_editor = v
		_update_multimesh_trees()

@export_group("Dimensões da Rua")
@export var half_width := 10.5:
	set(v):
		half_width = maxf(v, 3.0)
		_queue_rebuild()
@export var curb_width := 1.1:
	set(v):
		curb_width = maxf(v, 0.2)
		_queue_rebuild()
@export var curb_height := 0.85:
	set(v):
		curb_height = maxf(v, 0.0)
		_queue_rebuild()
@export var cross_slices := 10:
	set(v):
		cross_slices = clampi(v, 4, 24)
		_queue_rebuild()
@export var sample_step := 2.8:
	set(v):
		sample_step = clampf(v, 1.5, 12.0)
		_queue_rebuild()

@export_group("Ondulação Base (Pumptrack Procedural)")
@export var procedural_waves_intensity := 1.0:
	set(v):
		procedural_waves_intensity = clampf(v, 0.0, 3.0)
		_queue_rebuild()
@export var lateral_pockets_intensity := 1.0:
	set(v):
		lateral_pockets_intensity = clampf(v, 0.0, 3.0)
		_queue_rebuild()
@export var crest_bumps_intensity := 1.0:
	set(v):
		crest_bumps_intensity = clampf(v, 0.0, 3.0)
		_queue_rebuild()

const TRACK_ZONE_SCRIPT := preload("res://scripts/track_zone.gd")
const CONTROL_POINTS_2D := [
	Vector2(-52, 0),
	Vector2(-15, -2),
	Vector2(35, 0),
	Vector2(68, 12),
	Vector2(76, 30),
	Vector2(62, 42),
	Vector2(52, 26),
	Vector2(28, 18),
	Vector2(4, 24),
	Vector2(-2, 34),
	Vector2(20, 44),
	Vector2(18, 56),
	Vector2(-15, 58),
	Vector2(-48, 56),
	Vector2(-60, 70),
	Vector2(-42, 84),
	Vector2(5, 82),
	Vector2(45, 76),
	Vector2(64, 92),
	Vector2(50, 110),
	Vector2(8, 112),
	Vector2(-35, 110),
	Vector2(-48, 120),
	Vector2(-25, 128),
	Vector2(5, 130),
	Vector2(18, 142),
	Vector2(-5, 152),
	Vector2(-38, 148),
	Vector2(-50, 162),
	Vector2(-30, 176),
	Vector2(15, 174),
	Vector2(55, 168),
	Vector2(72, 180),
	Vector2(52, 194),
	Vector2(10, 192),
	Vector2(-10, 198),
	Vector2(5, 210),
	Vector2(18, 226),
	Vector2(16, 250),
	Vector2(10, 272),
	Vector2(-25, 274),
	Vector2(-58, 282),
	Vector2(-68, 298),
	Vector2(-52, 310),
	Vector2(-5, 308),
	Vector2(18, 318),
	Vector2(26, 338),
	Vector2(26, 355),
]
const WORLD_SCALE := 11.2
const BASE_SLOPE := 0.082

var samples: Array[Dictionary] = []
var total_length := 0.0
var _rebuild_timer := 0.0
var _zones_cache: Array[Dictionary] = []


func _ready() -> void:
	_ensure_editor_nodes()
	_apply_editor_perf_settings()
	rebuild_track()
	_update_multimesh_trees()


func _apply_editor_perf_settings() -> void:
	if not is_inside_tree():
		return
	var is_ed := Engine.is_editor_hint() and editor_fast_mode
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.shadow_enabled = not is_ed
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and we.environment:
		if is_ed:
			we.environment.background_mode = Environment.BG_COLOR
			we.environment.background_color = Color(0.55, 0.72, 0.92)
			we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			we.environment.ambient_light_color = Color(0.85, 0.88, 0.92)
			we.environment.fog_enabled = false
		else:
			if we.environment.sky == null:
				var sky_mat := ProceduralSkyMaterial.new()
				sky_mat.sky_top_color = Color(0.26, 0.52, 0.88)
				sky_mat.sky_horizon_color = Color(0.78, 0.86, 0.96)
				sky_mat.ground_horizon_color = Color(0.68, 0.78, 0.72)
				sky_mat.ground_bottom_color = Color(0.28, 0.38, 0.28)
				var sky := Sky.new()
				sky.sky_material = sky_mat
				we.environment.sky = sky
			we.environment.background_mode = Environment.BG_SKY
			we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
			we.environment.fog_enabled = true


func _process(delta: float) -> void:
	if _rebuild_timer > 0.0:
		_rebuild_timer -= delta
		if _rebuild_timer <= 0.0:
			rebuild_track()


func _queue_rebuild() -> void:
	if not is_inside_tree():
		return
	_rebuild_timer = 0.12 if Engine.is_editor_hint() else 0.01


# ----------------------------------------------------------------- Nós editáveis na cena

func _ensure_editor_nodes() -> void:
	if get_node_or_null("WorldEnvironment") == null:
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = Color(0.26, 0.52, 0.88)
		sky_mat.sky_horizon_color = Color(0.78, 0.86, 0.96)
		sky_mat.ground_horizon_color = Color(0.68, 0.78, 0.72)
		sky_mat.ground_bottom_color = Color(0.28, 0.38, 0.28)
		var sky := Sky.new()
		sky.sky_material = sky_mat
		var env := Environment.new()
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.95
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.fog_enabled = true
		env.fog_light_color = Color(0.76, 0.85, 0.95)
		env.fog_density = 0.0014
		var we := WorldEnvironment.new()
		we.name = "WorldEnvironment"
		we.environment = env
		add_child(we)
		_set_editable_owner(we)

	if get_node_or_null("Sun") == null:
		var sun := DirectionalLight3D.new()
		sun.name = "Sun"
		sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-32.0), 0.0)
		sun.light_energy = 1.15
		sun.shadow_enabled = not Engine.is_editor_hint()
		sun.directional_shadow_max_distance = 75.0
		add_child(sun)
		_set_editable_owner(sun)

	var path := get_node_or_null("TrackPath") as Path3D
	if path == null:
		path = Path3D.new()
		path.name = "TrackPath"
		add_child(path)
		_set_editable_owner(path)
	if path.curve == null or path.curve.point_count < 2:
		path.curve = _create_default_curve()
	if not path.curve_changed.is_connected(_queue_rebuild):
		path.curve_changed.connect(_queue_rebuild)

	var zones := get_node_or_null("TrackZones") as Node3D
	if zones == null:
		zones = Node3D.new()
		zones.name = "TrackZones"
		add_child(zones)
		_set_editable_owner(zones)
		_populate_default_zones(zones)

	# Pasta limpa para você colocar seus próprios objetos 3D / modelos do Blender!
	var scenery := get_node_or_null("Scenery") as Node3D
	if scenery == null:
		scenery = Node3D.new()
		scenery.name = "Scenery"
		add_child(scenery)
		_set_editable_owner(scenery)

	var gen := get_node_or_null("GeneratedTrack") as Node3D
	if gen == null:
		gen = Node3D.new()
		gen.name = "GeneratedTrack"
		add_child(gen)


func _set_editable_owner(node: Node) -> void:
	if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
		node.owner = get_tree().edited_scene_root


func _populate_default_zones(zones_parent: Node3D) -> void:
	var z1: Node3D = TRACK_ZONE_SCRIPT.new()
	z1.name = "DecliveForte_Dir_01"
	z1.position = Vector3(-165.0, -35.0, -18.0)
	z1.set("depth_offset", -2.4)
	z1.set("zone_width", 5.5)
	z1.set("zone_length", 18.0)
	zones_parent.add_child(z1)
	_set_editable_owner(z1)

	var z2: Node3D = TRACK_ZONE_SCRIPT.new()
	z2.name = "LombadaSalto_Esq_01"
	z2.position = Vector3(-95.0, -42.0, -12.0)
	z2.set("depth_offset", 1.9)
	z2.set("zone_width", 5.0)
	z2.set("zone_length", 12.0)
	zones_parent.add_child(z2)
	_set_editable_owner(z2)

	var z3: Node3D = TRACK_ZONE_SCRIPT.new()
	z3.name = "DecliveCurva_Interna_02"
	z3.position = Vector3(390.0, -88.0, 2.0)
	z3.set("depth_offset", -2.8)
	z3.set("zone_width", 6.0)
	z3.set("zone_length", 22.0)
	zones_parent.add_child(z3)
	_set_editable_owner(z3)


func _create_default_curve() -> Curve3D:
	var c := Curve3D.new()
	c.bake_interval = sample_step
	c.up_vector_enabled = true
	var n := CONTROL_POINTS_2D.size()
	var dist := 0.0
	var pts3d: Array[Vector3] = []
	for i in n:
		var p2: Vector2 = CONTROL_POINTS_2D[i] * WORLD_SCALE
		if i > 0:
			var prev2: Vector2 = CONTROL_POINTS_2D[i - 1] * WORLD_SCALE
			dist += p2.distance_to(prev2)
		var y := -dist * BASE_SLOPE
		pts3d.append(Vector3(p2.x, y, p2.y))
	for i in n:
		var prev_p := pts3d[maxi(0, i - 1)]
		var next_p := pts3d[mini(n - 1, i + 1)]
		var tangent := (next_p - prev_p) * 0.28
		c.add_point(pts3d[i], -tangent, tangent)
	return c


func reset_default_curve() -> void:
	_ensure_editor_nodes()
	var path := get_node("TrackPath") as Path3D
	path.curve = _create_default_curve()
	rebuild_track()


# ----------------------------------------------------------------- Reconstrução da Pista

func rebuild_track() -> void:
	_ensure_editor_nodes()
	_cache_track_zones()
	_generate_centerline_from_path()

	var gen := get_node("GeneratedTrack") as Node3D
	for child in gen.get_children():
		child.free()

	_build_track_chunks(gen)
	_build_start_and_finish_banners(gen)


func _cache_track_zones() -> void:
	_zones_cache.clear()
	var zones_node := get_node_or_null("TrackZones")
	if zones_node == null:
		return
	for child in zones_node.get_children():
		if child is Node3D and child.visible:
			var depth := 0.0
			if "depth_offset" in child:
				depth = float(child.get("depth_offset"))
			else:
				depth = child.scale.y
			var radius_xz := Vector2(maxf(absf(child.scale.x) * 8.0, 3.0), maxf(absf(child.scale.z) * 14.0, 4.0))
			if "zone_width" in child and "zone_length" in child:
				radius_xz = Vector2(maxf(float(child.get("zone_width")), 2.0), maxf(float(child.get("zone_length")), 2.0))
			_zones_cache.append({
				"inv_xform": child.global_transform.affine_inverse(),
				"depth": depth,
				"size": radius_xz,
			})


func _effective_step() -> float:
	if Engine.is_editor_hint() and editor_fast_mode:
		return maxf(sample_step, 14.0)
	return sample_step


func _effective_slices() -> int:
	if Engine.is_editor_hint() and editor_fast_mode:
		return 4
	return cross_slices


func _generate_centerline_from_path() -> void:
	var path := get_node("TrackPath") as Path3D
	var curve := path.curve
	# NUNCA altere curve.bake_interval aqui! Mudar qualquer propriedade da Curve3D
	# dispara o sinal curve_changed, o que criava um loop infinito reconstruindo a
	# pista a cada 0.12s no Editor (travando o editor em 6 FPS!).
	var total_len := curve.get_baked_length()
	var step := _effective_step()
	samples.clear()
	if total_len <= 0.1:
		total_length = 0.0
		return
	var count := maxi(2, int(ceil(total_len / step)) + 1)
	for i in count:
		var d := minf(float(i) * step, total_len)
		var xform := curve.sample_baked_with_rotation(d, true, true)
		var wp := path.to_global(xform.origin)
		var d_prev := maxf(0.0, d - step * 0.5)
		var d_next := minf(total_len, d + step * 0.5)
		var prev_p := path.to_global(curve.sample_baked(d_prev, true))
		var next_p := path.to_global(curve.sample_baked(d_next, true))
		var fwd := (next_p - prev_p)
		fwd.y = 0.0
		if fwd.length_squared() < 0.0001:
			fwd = Vector3.FORWARD
		else:
			fwd = fwd.normalized()
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		# Extrai o tilt lateral da base da curva
		var up_local := xform.basis.y
		var tilt_angle := asin(clampf(up_local.dot(right), -1.0, 1.0))
		samples.append({
			"pos": wp,
			"fwd": fwd,
			"right": right,
			"tilt": tilt_angle,
			"dist": d,
		})
	total_length = total_len


func _surface_height(d: float, lat: float, base_pos: Vector3, right: Vector3, tilt_angle: float) -> float:
	var base_y := base_pos.y + sin(tilt_angle) * lat
	var env := smoothstep(12.0, 42.0, d) * (1.0 - smoothstep(total_length - 45.0, total_length - 12.0, d))

	var u := clampf(lat / half_width, -1.0, 1.0)
	var center_wave := (sin(d * 0.075) * 1.45 + sin(d * 0.16 + 1.1) * 0.75) * procedural_waves_intensity
	var side_tilt := (sin(d * 0.095 + 0.4) * 1.65 + cos(d * 0.185 - 0.8) * 1.05) * u * lateral_pockets_intensity
	var channel_wave := sin(d * 0.13 + 2.2) * (u * u - 0.45) * 1.55 * lateral_pockets_intensity
	var bump_phase := sin(d * 0.22 + u * 1.7)
	var sharp_crest := pow(maxf(0.0, bump_phase), 3.0) * 1.35 * crest_bumps_intensity

	var y := base_y + (center_wave + side_tilt + channel_wave + sharp_crest) * env

	if not _zones_cache.is_empty():
		var world_xz := Vector3(base_pos.x, base_y, base_pos.z) + right * lat
		for z in _zones_cache:
			var local_p: Vector3 = z["inv_xform"] * world_xz
			var sz: Vector2 = z["size"]
			var nx := local_p.x / sz.x
			var nz := local_p.z / sz.y
			var r2 := nx * nx + nz * nz
			if r2 < 1.0:
				var falloff := (1.0 - r2) * (1.0 - r2)
				y += float(z["depth"]) * falloff
	return y


func _build_track_chunks(parent: Node3D) -> void:
	if samples.size() < 2:
		return
	var road_mat := StandardMaterial3D.new()
	road_mat.vertex_color_use_as_albedo = true
	road_mat.roughness = 0.88
	if Engine.is_editor_hint() and editor_fast_mode:
		road_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Divide a pista em blocos de ~120 anéis para Frustum Culling imediato da GPU (tanto no Editor quanto no jogo!)
	var chunk_size := 60 if (Engine.is_editor_hint() and editor_fast_mode) else 140
	var num_samples := samples.size()
	var start_idx := 0
	while start_idx < num_samples - 1:
		var end_idx := mini(start_idx + chunk_size, num_samples - 1)
		_build_single_chunk(parent, start_idx, end_idx, road_mat)
		start_idx = end_idx


func _build_single_chunk(parent: Node3D, i_start: int, i_end: int, mat: Material) -> void:
	var slices := _effective_slices()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rings: Array = []
	for i in range(i_start, i_end + 1):
		var s := samples[i]
		var d: float = s["dist"]
		var cpos: Vector3 = s["pos"]
		var right: Vector3 = s["right"]
		var tilt_angle: float = s["tilt"]
		var ring_pts: Array[Vector3] = []
		for j in range(slices + 1):
			var frac := float(j) / float(slices)
			var lat := lerpf(-half_width, half_width, frac)
			var y := _surface_height(d, lat, cpos, right, tilt_angle)
			ring_pts.append(Vector3(cpos.x, y, cpos.z) + right * lat)
		rings.append(ring_pts)

	for r in range(rings.size() - 1):
		var i := i_start + r
		var d0: float = samples[i]["dist"]
		var d1: float = samples[i + 1]["dist"]
		var cpos0: Vector3 = samples[i]["pos"]
		var cpos1: Vector3 = samples[i + 1]["pos"]
		var c_drop: float = (cpos0.y - cpos1.y) / maxf(d1 - d0, 0.01)
		var row0: Array[Vector3] = rings[r]
		var row1: Array[Vector3] = rings[r + 1]

		for j in range(slices):
			var p00 := row0[j]
			var p01 := row0[j + 1]
			var p10 := row1[j]
			var p11 := row1[j + 1]

			var avg_y0 := (p00.y + p01.y) * 0.5
			var avg_y1 := (p10.y + p11.y) * 0.5
			var local_drop: float = (avg_y0 - avg_y1) / maxf(d1 - d0, 0.01)
			var delta_slope: float = local_drop - c_drop

			var col := _slope_color(delta_slope, j, i, slices)
			_add_quad(st, p00, p01, p11, p10, col)

		var curb_col := Color(0.92, 0.2, 0.18) if (i / 2) % 2 == 0 else Color(0.95, 0.95, 0.95)
		var r0: Vector3 = samples[i]["right"]
		var r1: Vector3 = samples[i + 1]["right"]

		# No editor_fast_mode desenhamos apenas 1 faixa de mureta simples de cada lado (metade dos polígonos)
		if Engine.is_editor_hint() and editor_fast_mode:
			var l_in0 := row0[0]
			var l_in1 := row1[0]
			var l_top0 := l_in0 + Vector3.UP * curb_height
			var l_top1 := l_in1 + Vector3.UP * curb_height
			_add_quad(st, l_top0, l_in0, l_in1, l_top1, curb_col)
			var r_in0 := row0[slices]
			var r_in1 := row1[slices]
			var r_top0 := r_in0 + Vector3.UP * curb_height
			var r_top1 := r_in1 + Vector3.UP * curb_height
			_add_quad(st, r_in0, r_top0, r_top1, r_in1, curb_col)
		else:
			var l_in0 := row0[0]
			var l_in1 := row1[0]
			var l_top0 := l_in0 - r0 * (curb_width * 0.3) + Vector3.UP * curb_height
			var l_top1 := l_in1 - r1 * (curb_width * 0.3) + Vector3.UP * curb_height
			var l_out0 := l_in0 - r0 * curb_width + Vector3.UP * curb_height
			var l_out1 := l_in1 - r1 * curb_width + Vector3.UP * curb_height
			_add_quad(st, l_top0, l_in0, l_in1, l_top1, curb_col)
			_add_quad(st, l_out0, l_top0, l_top1, l_out1, curb_col.darkened(0.15))

			var r_in0 := row0[slices]
			var r_in1 := row1[slices]
			var r_top0 := r_in0 + r0 * (curb_width * 0.3) + Vector3.UP * curb_height
			var r_top1 := r_in1 + r1 * (curb_width * 0.3) + Vector3.UP * curb_height
			var r_out0 := r_in0 + r0 * curb_width + Vector3.UP * curb_height
			var r_out1 := r_in1 + r1 * curb_width + Vector3.UP * curb_height
			_add_quad(st, r_in0, r_top0, r_top1, r_in1, curb_col)
			_add_quad(st, r_top0, r_out0, r_out1, r_top1, curb_col.darkened(0.15))

	if not (Engine.is_editor_hint() and editor_fast_mode):
		st.generate_normals()
	var mesh := st.commit()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

	# CRÍTICO PARA PERFORMANCE NO EDITOR:
	# Não adiciona CollisionShape3D quando está no Editor 3D (evita desenhar 50.000 linhas de gizmo!)
	if not Engine.is_editor_hint():
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		var shape := mesh.create_trimesh_shape()
		shape.backface_collision = true
		cs.shape = shape
		body.add_child(cs)
		parent.add_child(body)


func _slope_color(delta_slope: float, slice_j: int, ring_i: int, slices: int) -> Color:
	var base := Color(0.25, 0.27, 0.31)
	if (ring_i / 3) % 2 == 0 and (slice_j == 0 or slice_j == slices - 1):
		base = base.lightened(0.05)
	if slice_j == slices / 2 and (ring_i % 6 < 3):
		base = Color(0.82, 0.78, 0.32)

	if delta_slope > 0.025:
		var t := clampf((delta_slope - 0.025) / 0.14, 0.0, 1.0)
		return base.lerp(Color(0.12, 0.68, 0.88), t * 0.78)
	elif delta_slope < -0.03:
		var t := clampf((-delta_slope - 0.03) / 0.14, 0.0, 1.0)
		return base.lerp(Color(0.92, 0.48, 0.18), t * 0.78)
	return base


func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	st.set_color(col)
	for v in [a, c, b, a, d, c]:
		st.add_vertex(v)


# ----------------------------------------------------------------- Spawns e Progresso

func get_spawn_point(slot: int) -> Dictionary:
	if samples.size() < 6:
		return {"pos": Vector3(0, 2, 0), "heading": 0.0}
	var col := slot % 3
	var row := slot / 3
	var idx := clampi(4 - row, 1, 6)
	var s := samples[idx]
	var lateral := (col - 1) * 3.2
	var p: Vector3 = s["pos"] + s["right"] * lateral
	p.y = _surface_height(s["dist"], lateral, s["pos"], s["right"], s["tilt"]) + 0.85
	var f: Vector3 = s["fwd"]
	var heading := atan2(-f.x, -f.z)
	return {"pos": p, "heading": heading}


func compute_progress(world_pos: Vector3) -> float:
	if samples.is_empty() or total_length <= 1.0:
		return 0.0
	var best_d2 := INF
	var best_dist := 0.0
	var step := 4
	var best_i := 0
	for i in range(0, samples.size(), step):
		var d2 := world_pos.distance_squared_to(samples[i]["pos"])
		if d2 < best_d2:
			best_d2 = d2
			best_i = i
	for j in range(maxi(0, best_i - step), mini(samples.size(), best_i + step + 1)):
		var d2 := world_pos.distance_squared_to(samples[j]["pos"])
		if d2 < best_d2:
			best_d2 = d2
			best_dist = samples[j]["dist"]
	return clampf(best_dist / total_length, 0.0, 1.0)


# ----------------------------------------------------------------- Pórticos e Árvores MultiMesh

func _build_start_and_finish_banners(parent: Node3D) -> void:
	if samples.size() < 12:
		return
	if Engine.is_editor_hint() and editor_fast_mode:
		return
	_build_arch(parent, samples[3], Color(0.2, 0.75, 0.35), "LARGADA — DESÇA O MORRO!")
	var finish_sample := samples[samples.size() - 4]
	_build_arch(parent, finish_sample, Color(0.95, 0.75, 0.15), "CHEGADA!")

	if not Engine.is_editor_hint():
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 2
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(half_width * 2.2, 8.0, 4.0)
		cs.shape = box
		area.add_child(cs)
		var f: Vector3 = finish_sample["fwd"]
		var heading := atan2(-f.x, -f.z)
		area.transform = Transform3D(Basis(Vector3.UP, heading), finish_sample["pos"] + Vector3.UP * 3.0)
		area.body_entered.connect(_on_finish_entered)
		parent.add_child(area)


func _build_arch(parent: Node3D, s: Dictionary, banner_color: Color, label_text: String) -> void:
	var root := Node3D.new()
	var f: Vector3 = s["fwd"]
	var heading := atan2(-f.x, -f.z)
	root.transform = Transform3D(Basis(Vector3.UP, heading), s["pos"])

	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color(0.2, 0.22, 0.25)
	var pillar_mesh := CylinderMesh.new()
	pillar_mesh.top_radius = 0.35
	pillar_mesh.bottom_radius = 0.35
	pillar_mesh.height = 7.0
	pillar_mesh.material = pillar_mat

	for side in [-1.0, 1.0]:
		var p := MeshInstance3D.new()
		p.mesh = pillar_mesh
		p.position = Vector3(side * (half_width + 0.5), 3.5, 0.0)
		root.add_child(p)

	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = banner_color
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(half_width * 2.2, 1.3, 0.5)
	beam_mesh.material = beam_mat
	var beam := MeshInstance3D.new()
	beam.mesh = beam_mesh
	beam.position = Vector3(0.0, 6.6, 0.0)
	root.add_child(beam)

	var lbl := Label3D.new()
	lbl.text = label_text
	lbl.font_size = 42
	lbl.outline_size = 10
	lbl.position = Vector3(0.0, 6.6, 0.3)
	root.add_child(lbl)
	parent.add_child(root)


func _on_finish_entered(body: Node3D) -> void:
	if body.has_meta("kart"):
		var k: Kart = body.get_meta("kart")
		if k.finished_time <= 0.0 and k.race_time > 10.0:
			k.finished_time = k.race_time


func _update_multimesh_trees() -> void:
	var gen := get_node_or_null("GeneratedTrack")
	if gen == null:
		return
	var old := gen.get_node_or_null("TreesMultiMesh")
	if old:
		old.free()
	if Engine.is_editor_hint() and not show_trees_in_editor:
		return
	if samples.is_empty():
		return

	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.2, 0.56, 0.28)
	var leaf_mesh := CylinderMesh.new()
	leaf_mesh.top_radius = 0.0
	leaf_mesh.bottom_radius = 2.4
	leaf_mesh.height = 6.2
	leaf_mesh.radial_segments = 6
	leaf_mesh.material = leaf_mat

	var step := 14
	var indices := range(10, samples.size() - 10, step)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = leaf_mesh
	mm.instance_count = indices.size()

	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for k in indices.size():
		var s := samples[indices[k]]
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var dist_out := half_width + rng.randf_range(5.0, 15.0)
		var sc := rng.randf_range(0.9, 1.5)
		var pos: Vector3 = s["pos"] + s["right"] * (side * dist_out) + Vector3.UP * (2.6 * sc)
		mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * sc), pos))

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "TreesMultiMesh"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gen.add_child(mmi)
