@tool
extends Node3D
## Pista de Descida de Morro (Rolimã Pumptrack) — Estética Retrô PS1 / N64 na Floresta Tropical!
##
## Usa os assets retrô da pasta `res://Assets/`:
## - Céu HDRI PS1 (`Assets/PSX_Daysky_HDRI/DAYSKY.hdr` ou `PSX_NIGHTSKY.hdr`)
## - Texturas pixeladas seamless 128x128 (`PSX_ForestGround_Tex/*` + `textures/Ps1Wood_baseColor.png`)
##   com filtro `NEAREST` (sem borrão bilinear, estilo PS1/N64 clássico!)
## - Chão de selva tropical margeando toda a descida + estrada de terra/cascalho/grama da mata
## - Árvores, rochas, troncos caídos, arbustos e flores tropicais espalhados via `MultiMeshInstance3D`
##   (alta densidade visual de floresta tropical mantendo 200+ FPS no Viewport e no navegador!)

@export_group("Reconstruir / Exportar")
@export_tool_button("Reconstruir Pista e Floresta Agora") var btn_rebuild := rebuild_track
@export_tool_button("Resetar Curva Padrão no TrackPath") var btn_reset_curve := reset_default_curve

@export_group("Estilo Visual Retrô (PS1 / N64)")
@export var night_mode := false: ## Alterna entre o céu DAYSKY.hdr (dia tropical) e PSX_NIGHTSKY.hdr (noite)
	set(v):
		night_mode = v
		_apply_editor_perf_settings()
@export var editor_fast_mode := false:
	set(v):
		editor_fast_mode = v
		_apply_editor_perf_settings()
		_queue_rebuild()
@export var show_trees_in_editor := true:
	set(v):
		show_trees_in_editor = v
		_update_tropical_forest()

@export_group("Dimensões da Rua e Terreno")
@export var half_width := 10.5:
	set(v):
		half_width = maxf(v, 3.0)
		_queue_rebuild()
@export var terrain_skirt_width := 52.0: ## Largura do chão da floresta tropical para cada lado da pista
	set(v):
		terrain_skirt_width = maxf(v, 12.0)
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

# Caminhos dos Assets Retrô (PS1 / N64)
const HDRI_DAY_PATH := "res://Assets/PSX_Daysky_HDRI/DAYSKY.hdr"
const HDRI_NIGHT_PATH := "res://Assets/PSX_Nightsky_HDRI/PSX_NIGHTSKY.hdr"
const TEX_ROAD_EARTH := "res://Assets/PSX_Forest_Level_byStarkCrafts/PSX_ForestGround_Tex/PSX_Seamless_ForestEarthGround_128px.png"
const TEX_ROAD_GRAVEL := "res://Assets/PSX_Forest_Level_byStarkCrafts/PSX_ForestGround_Tex/PSX_Seamless_ForestGravel_Ground_128px.png"
const TEX_JUNGLE_GRASS := "res://Assets/PSX_Forest_Level_byStarkCrafts/PSX_ForestGround_Tex/PSX_Seamless_WildForestGrass_128px.png"
const TEX_JUNGLE_CLOVER := "res://Assets/PSX_Forest_Level_byStarkCrafts/PSX_ForestGround_Tex/PSX_Seamless_WildForestClover_128px.png"
const TEX_PS1_WOOD := "res://Assets/textures/Ps1Wood_baseColor.png"

const RETRO_TREE_GLBS := [
	"res://Assets/Retro Tree Pack v1.0/Retro Tree Pack/Models/Super Low Res/GLB/tree_rt_1.glb",
	"res://Assets/Retro Tree Pack v1.0/Retro Tree Pack/Models/Super Low Res/GLB/tree_rt_2.glb",
	"res://Assets/Retro Tree Pack v1.0/Retro Tree Pack/Models/Super Low Res/GLB/tree_rt_3.glb",
	"res://Assets/Retro Tree Pack v1.0/Retro Tree Pack/Models/Super Low Res/GLB/tree_rt_4.glb",
	"res://Assets/Retro Tree Pack v1.0/Retro Tree Pack/Models/Super Low Res/GLB/small_tree_rt_1.glb",
	"res://Assets/Retro Tree Pack v1.0/Retro Tree Pack/Models/Super Low Res/GLB/dead_tree_rt_1.glb",
]
const PSX_FOREST_FBX := "res://Assets/PSX_Forest_Level_byStarkCrafts/PSX_Forest_AssetCollection_byStarkCrafts.fbx"
const PSX_GLTF_SCENE := "res://Assets/scene.gltf"

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
var _mesh_cache: Dictionary = {}
var _packed_cache: Dictionary = {}


func _ready() -> void:
	_ensure_editor_nodes()
	_apply_editor_perf_settings()
	rebuild_track()


func _process(delta: float) -> void:
	if _rebuild_timer > 0.0:
		_rebuild_timer -= delta
		if _rebuild_timer <= 0.0:
			rebuild_track()


func _queue_rebuild() -> void:
	if not is_inside_tree():
		return
	_rebuild_timer = 0.12 if Engine.is_editor_hint() else 0.01


# ----------------------------------------------------------------- Ambiente HDRI PS1 & Nós Editáveis

func _apply_editor_perf_settings() -> void:
	if not is_inside_tree():
		return
	var is_ed := Engine.is_editor_hint() and editor_fast_mode
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.shadow_enabled = not is_ed
		sun.light_color = Color(1.0, 0.95, 0.84) if not night_mode else Color(0.55, 0.68, 0.95)
		sun.light_energy = 1.2 if not night_mode else 0.55

	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and we.environment:
		if is_ed:
			we.environment.background_mode = Environment.BG_COLOR
			we.environment.background_color = Color(0.55, 0.72, 0.92)
			we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			we.environment.ambient_light_color = Color(0.85, 0.88, 0.92)
			we.environment.fog_enabled = false
		else:
			var hdri_path := HDRI_NIGHT_PATH if night_mode else HDRI_DAY_PATH
			if ResourceLoader.exists(hdri_path):
				var pano_mat := PanoramaSkyMaterial.new()
				pano_mat.panorama = load(hdri_path)
				pano_mat.filter = false # Pixelado retrô PS1 no céu!
				var sky := Sky.new()
				sky.sky_material = pano_mat
				we.environment.sky = sky
			we.environment.background_mode = Environment.BG_SKY
			we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
			we.environment.ambient_light_sky_contribution = 0.75
			we.environment.ambient_light_energy = 1.05 if not night_mode else 0.55
			we.environment.fog_enabled = true
			# Neblina úmida de floresta tropical estilo N64/PS1
			we.environment.fog_light_color = Color(0.58, 0.78, 0.72) if not night_mode else Color(0.12, 0.18, 0.28)
			we.environment.fog_density = 0.0018
			we.environment.fog_sky_affect = 0.35


func _ensure_editor_nodes() -> void:
	if get_node_or_null("WorldEnvironment") == null:
		var env := Environment.new()
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		var we := WorldEnvironment.new()
		we.name = "WorldEnvironment"
		we.environment = env
		add_child(we)
		_set_editable_owner(we)

	if get_node_or_null("Sun") == null:
		var sun := DirectionalLight3D.new()
		sun.name = "Sun"
		sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-32.0), 0.0)
		sun.light_energy = 1.2
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 85.0
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


# ----------------------------------------------------------------- Reconstrução da Pista e Chão da Selva

func rebuild_track() -> void:
	_ensure_editor_nodes()
	_cache_track_zones()
	_generate_centerline_from_path()

	var gen := get_node("GeneratedTrack") as Node3D
	for child in gen.get_children():
		child.free()

	_build_track_and_jungle_chunks(gen)
	_build_start_and_finish_banners(gen)
	_update_tropical_forest()


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
		return maxf(sample_step, 12.0)
	return sample_step


func _effective_slices() -> int:
	if Engine.is_editor_hint() and editor_fast_mode:
		return 4
	return cross_slices


func _generate_centerline_from_path() -> void:
	var path := get_node("TrackPath") as Path3D
	var curve := path.curve
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


## Altura do chão da floresta tropical nas laterais da pista (`side_sign` = -1 esquerda, +1 direita,
## `out_dist` = distância para fora a partir da borda da pista).
func _jungle_ground_height(s: Dictionary, side_sign: float, out_dist: float) -> float:
	var d: float = s["dist"]
	var cpos: Vector3 = s["pos"]
	var right: Vector3 = s["right"]
	var tilt_angle: float = s["tilt"]
	var edge_lat := side_sign * half_width
	var edge_y := _surface_height(d, edge_lat, cpos, right, tilt_angle)
	if out_dist <= 0.1:
		return edge_y
	# Faz uma ribanceira/barranco tropical suave ondulado ao redor da trilha
	var hill := sin(d * 0.045 + side_sign * 1.3) * 3.8 + cos(d * 0.11 - side_sign * 0.7) * 1.8
	var rise := (out_dist / terrain_skirt_width) * (4.5 + hill) + sin(out_dist * 0.18 + d * 0.06) * 1.1
	return edge_y + rise


func _make_psx_material(tex_path: String, use_vertex_color := true, roughness_val := 0.92) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = use_vertex_color
	mat.roughness = roughness_val
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	if ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path)
	return mat


func _build_track_and_jungle_chunks(parent: Node3D) -> void:
	if samples.size() < 2:
		return
	# Estrada de terra/cascalho da selva com textura PSX 128px + leitura de relevo nas cores de vértice!
	var road_mat := _make_psx_material(TEX_ROAD_GRAVEL, true, 0.9)
	# Chão da floresta tropical com textura PSX WildForestGrass 128px!
	var jungle_mat := _make_psx_material(TEX_JUNGLE_GRASS, true, 0.96)

	var chunk_size := 120
	var num_samples := samples.size()
	var start_idx := 0
	while start_idx < num_samples - 1:
		var end_idx := mini(start_idx + chunk_size, num_samples - 1)
		_build_single_chunk(parent, start_idx, end_idx, road_mat, jungle_mat)
		start_idx = end_idx


func _build_single_chunk(parent: Node3D, i_start: int, i_end: int, road_mat: Material, jungle_mat: Material) -> void:
	var slices := _effective_slices()
	var st_road := SurfaceTool.new()
	st_road.begin(Mesh.PRIMITIVE_TRIANGLES)

	var st_jungle := SurfaceTool.new()
	st_jungle.begin(Mesh.PRIMITIVE_TRIANGLES)

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

	var uv_scale_road := 0.16
	var uv_scale_jungle := 0.12
	var skirt_steps := [0.0, 12.0, 28.0, terrain_skirt_width]

	for r in range(rings.size() - 1):
		var i := i_start + r
		var d0: float = samples[i]["dist"]
		var d1: float = samples[i + 1]["dist"]
		var cpos0: Vector3 = samples[i]["pos"]
		var cpos1: Vector3 = samples[i + 1]["pos"]
		var c_drop: float = (cpos0.y - cpos1.y) / maxf(d1 - d0, 0.01)
		var row0: Array[Vector3] = rings[r]
		var row1: Array[Vector3] = rings[r + 1]
		var r0: Vector3 = samples[i]["right"]
		var r1: Vector3 = samples[i + 1]["right"]

		# 1. Superfície da pista com UVs mapeados para a textura retrô PSX + cores de declive/aclive
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
			var u0 := float(j) / float(slices) * (half_width * 2.0 * uv_scale_road)
			var u1 := float(j + 1) / float(slices) * (half_width * 2.0 * uv_scale_road)
			var v0 := d0 * uv_scale_road
			var v1 := d1 * uv_scale_road
			_add_quad_uv(st_road, p00, p01, p11, p10, Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1), col)

		# 2. Muretas de toras de madeira / pedra musgosa nas bordas da trilha tropical
		var curb_col := Color(0.58, 0.4, 0.24) if (i / 2) % 2 == 0 else Color(0.42, 0.52, 0.28)
		var cv0 := d0 * uv_scale_road
		var cv1 := d1 * uv_scale_road

		var l_in0 := row0[0]
		var l_in1 := row1[0]
		var l_top0 := l_in0 - r0 * (curb_width * 0.3) + Vector3.UP * curb_height
		var l_top1 := l_in1 - r1 * (curb_width * 0.3) + Vector3.UP * curb_height
		var l_out0 := l_in0 - r0 * curb_width + Vector3.UP * curb_height
		var l_out1 := l_in1 - r1 * curb_width + Vector3.UP * curb_height
		_add_quad_uv(st_road, l_top0, l_in0, l_in1, l_top1, Vector2(0, cv0), Vector2(0.3, cv0), Vector2(0.3, cv1), Vector2(0, cv1), curb_col)
		_add_quad_uv(st_road, l_out0, l_top0, l_top1, l_out1, Vector2(0, cv0), Vector2(0.3, cv0), Vector2(0.3, cv1), Vector2(0, cv1), curb_col.darkened(0.15))

		var r_in0 := row0[slices]
		var r_in1 := row1[slices]
		var r_top0 := r_in0 + r0 * (curb_width * 0.3) + Vector3.UP * curb_height
		var r_top1 := r_in1 + r1 * (curb_width * 0.3) + Vector3.UP * curb_height
		var r_out0 := r_in0 + r0 * curb_width + Vector3.UP * curb_height
		var r_out1 := r_in1 + r1 * curb_width + Vector3.UP * curb_height
		_add_quad_uv(st_road, r_in0, r_top0, r_top1, r_in1, Vector2(0, cv0), Vector2(0.3, cv0), Vector2(0.3, cv1), Vector2(0, cv1), curb_col)
		_add_quad_uv(st_road, r_top0, r_out0, r_out1, r_top1, Vector2(0, cv0), Vector2(0.3, cv0), Vector2(0.3, cv1), Vector2(0, cv1), curb_col.darkened(0.15))

		# 3. Chão da Floresta Tropical margeando os dois lados da descida (com textura PS1 de grama da selva!)
		for side: float in [-1.0, 1.0]:
			for s_idx in range(skirt_steps.size() - 1):
				var od_a: float = skirt_steps[s_idx]
				var od_b: float = skirt_steps[s_idx + 1]
				var lat_a := side * (half_width + curb_width + od_a)
				var lat_b := side * (half_width + curb_width + od_b)
				var ya0 := _jungle_ground_height(samples[i], side, od_a)
				var yb0 := _jungle_ground_height(samples[i], side, od_b)
				var ya1 := _jungle_ground_height(samples[i + 1], side, od_a)
				var yb1 := _jungle_ground_height(samples[i + 1], side, od_b)

				var pa0 := Vector3(cpos0.x, ya0, cpos0.z) + r0 * lat_a
				var pb0 := Vector3(cpos0.x, yb0, cpos0.z) + r0 * lat_b
				var pa1 := Vector3(cpos1.x, ya1, cpos1.z) + r1 * lat_a
				var pb1 := Vector3(cpos1.x, yb1, cpos1.z) + r1 * lat_b

				var j_col := Color(0.85, 0.95, 0.8) if s_idx % 2 == 0 else Color(0.72, 0.88, 0.7)
				var ju0 := od_a * uv_scale_jungle
				var ju1 := od_b * uv_scale_jungle
				var jv0 := d0 * uv_scale_jungle
				var jv1 := d1 * uv_scale_jungle
				if side > 0.0:
					_add_quad_uv(st_jungle, pa0, pb0, pb1, pa1, Vector2(ju0, jv0), Vector2(ju1, jv0), Vector2(ju1, jv1), Vector2(ju0, jv1), j_col)
				else:
					_add_quad_uv(st_jungle, pb0, pa0, pa1, pb1, Vector2(ju1, jv0), Vector2(ju0, jv0), Vector2(ju0, jv1), Vector2(ju1, jv1), j_col)

	st_road.generate_normals()
	var road_mesh := st_road.commit()
	var mi_road := MeshInstance3D.new()
	mi_road.mesh = road_mesh
	mi_road.material_override = road_mat
	mi_road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi_road)

	st_jungle.generate_normals()
	var jungle_mesh := st_jungle.commit()
	var mi_jungle := MeshInstance3D.new()
	mi_jungle.mesh = jungle_mesh
	mi_jungle.material_override = jungle_mat
	mi_jungle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi_jungle)

	if not Engine.is_editor_hint():
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		var shape := road_mesh.create_trimesh_shape()
		shape.backface_collision = true
		cs.shape = shape
		body.add_child(cs)
		parent.add_child(body)


func _slope_color(delta_slope: float, slice_j: int, ring_i: int, slices: int) -> Color:
	# Em cima da textura PSX de terra/cascalho, modulamos a cor para manter a leitura clara do Pumptrack!
	var base := Color(0.78, 0.72, 0.62)
	if (ring_i / 3) % 2 == 0 and (slice_j == 0 or slice_j == slices - 1):
		base = Color(0.68, 0.78, 0.58) # Borda com musgo tropical
	if slice_j == slices / 2 and (ring_i % 6 < 3):
		base = Color(0.95, 0.88, 0.52) # Trilha central marcada

	if delta_slope > 0.025:
		var t := clampf((delta_slope - 0.025) / 0.14, 0.0, 1.0)
		return base.lerp(Color(0.22, 0.92, 1.0), t * 0.82)
	elif delta_slope < -0.03:
		var t := clampf((-delta_slope - 0.03) / 0.14, 0.0, 1.0)
		return base.lerp(Color(1.0, 0.52, 0.18), t * 0.82)
	return base


func _add_quad_uv(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uva: Vector2, uvb: Vector2, uvc: Vector2, uvd: Vector2, col: Color) -> void:
	st.set_color(col)
	var verts := [a, c, b, a, d, c]
	var uvs := [uva, uvc, uvb, uva, uvd, uvc]
	for k in 6:
		st.set_uv(uvs[k])
		st.add_vertex(verts[k])


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


# ----------------------------------------------------------------- Pórticos Retrô de Madeira & Floresta Tropical

func _build_start_and_finish_banners(parent: Node3D) -> void:
	if samples.size() < 12:
		return
	if Engine.is_editor_hint() and editor_fast_mode:
		return
	_build_arch(parent, samples[3], Color(0.35, 0.85, 0.42), "LARGADA — SELVA TROPICAL!")
	var finish_sample := samples[samples.size() - 4]
	_build_arch(parent, finish_sample, Color(0.98, 0.8, 0.2), "CHEGADA!")

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

	var wood_mat := _make_psx_material(TEX_PS1_WOOD, false, 0.85)
	var pillar_mesh := CylinderMesh.new()
	pillar_mesh.top_radius = 0.42
	pillar_mesh.bottom_radius = 0.5
	pillar_mesh.height = 7.2
	pillar_mesh.radial_segments = 6
	pillar_mesh.material = wood_mat

	for side: float in [-1.0, 1.0]:
		var p := MeshInstance3D.new()
		p.mesh = pillar_mesh
		p.position = Vector3(side * (half_width + 0.5), 3.5, 0.0)
		root.add_child(p)

	var beam_mat := _make_psx_material(TEX_PS1_WOOD, false, 0.8)
	beam_mat.albedo_color = banner_color
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(half_width * 2.2, 1.4, 0.6)
	beam_mesh.material = beam_mat
	var beam := MeshInstance3D.new()
	beam.mesh = beam_mesh
	beam.position = Vector3(0.0, 6.6, 0.0)
	root.add_child(beam)

	var lbl := Label3D.new()
	lbl.text = label_text
	lbl.font_size = 42
	lbl.outline_size = 10
	lbl.position = Vector3(0.0, 6.6, 0.35)
	root.add_child(lbl)
	parent.add_child(root)


func _on_finish_entered(body: Node3D) -> void:
	if body.has_meta("kart"):
		var k: Kart = body.get_meta("kart")
		if k.finished_time <= 0.0 and k.race_time > 10.0:
			k.finished_time = k.race_time


## Extrai o primeiro Mesh de uma cena importada (.glb / .fbx) e aplica filtro NEAREST (estilo PS1/N64)
## nas texturas de todas as superfícies.
func _extract_retro_mesh(scene_path: String, child_name := "") -> Dictionary:
	var cache_key := scene_path + "::" + child_name
	if _mesh_cache.has(cache_key):
		return (_mesh_cache[cache_key] as Dictionary).duplicate()
	if not ResourceLoader.exists(scene_path):
		return {}
	if not _packed_cache.has(scene_path):
		_packed_cache[scene_path] = load(scene_path)
	var packed := _packed_cache[scene_path] as PackedScene
	if packed == null:
		return {}
	var inst := packed.instantiate()
	var target_mi: MeshInstance3D = null
	if child_name != "":
		target_mi = inst.find_child(child_name + "*", true, false) as MeshInstance3D
	if target_mi == null:
		var all := inst.find_children("*", "MeshInstance3D", true, false)
		if not all.is_empty():
			target_mi = all[0] as MeshInstance3D
	var result := {}
	if target_mi and target_mi.mesh:
		var mesh_copy: Mesh = target_mi.mesh.duplicate()
		for surf_idx in mesh_copy.get_surface_count():
			var mat := target_mi.get_active_material(surf_idx)
			if mat is BaseMaterial3D:
				var m_copy: BaseMaterial3D = mat.duplicate()
				m_copy.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
				m_copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				m_copy.alpha_scissor_threshold = 0.45
				m_copy.cull_mode = BaseMaterial3D.CULL_DISABLED
				mesh_copy.surface_set_material(surf_idx, m_copy)
		result = {
			"mesh": mesh_copy,
			"basis": target_mi.transform.basis,
		}
		_mesh_cache[cache_key] = result
	inst.free()
	return result.duplicate()


## Espalha as árvores frondosas, palmeiras/arbustos, rochas e troncos caídos da pasta `Assets/`
## ao longo das duas margens da descida tropical usando `MultiMeshInstance3D` (rápido e leve!).
func _update_tropical_forest() -> void:
	var gen := get_node_or_null("GeneratedTrack")
	if gen == null:
		return
	var old := gen.get_node_or_null("TropicalForest")
	if old:
		old.free()
	if Engine.is_editor_hint() and not show_trees_in_editor:
		return
	if samples.size() < 10:
		return

	var forest_root := Node3D.new()
	forest_root.name = "TropicalForest"
	gen.add_child(forest_root)

	# 1. Carrega as árvores do Retro Tree Pack v1.0 (Super Low Res GLB) + árvores PSX_Forest_Level
	var tree_entries: Array[Dictionary] = []
	var tree_scales := [4.2, 2.6, 3.0, 2.3, 4.5, 2.2]
	for idx in RETRO_TREE_GLBS.size():
		var data := _extract_retro_mesh(RETRO_TREE_GLBS[idx])
		if not data.is_empty():
			data["scale"] = tree_scales[idx]
			data["transforms"] = []
			tree_entries.append(data)
	for psx_tree in ["PSX_Tree1", "PSX_Tree2", "PSX_Tree4"]:
		var tdata := _extract_retro_mesh(PSX_FOREST_FBX, psx_tree)
		if not tdata.is_empty():
			tdata["scale"] = 135.0
			tdata["transforms"] = []
			tree_entries.append(tdata)

	# 2. Carrega pedras, troncos caídos, arbustos e plantas tropicais do pacote PSX_Forest_Level + scene.gltf
	var prop_defs := [
		{"scene": PSX_FOREST_FBX, "name": "PSX_Rock", "scale": 135.0},
		{"scene": PSX_FOREST_FBX, "name": "PSX_Treetrunk", "scale": 140.0},
		{"scene": PSX_FOREST_FBX, "name": "PSX_Reed", "scale": 160.0},
		{"scene": PSX_FOREST_FBX, "name": "PSX_Grass", "scale": 165.0},
		{"scene": PSX_FOREST_FBX, "name": "PSX_Lavender", "scale": 140.0},
		{"scene": PSX_FOREST_FBX, "name": "PSX_Dandelion", "scale": 150.0},
		{"scene": "res://Assets/scene.gltf", "name": "PS1Bush_5", "scale": 1.15},
		{"scene": "res://Assets/scene.gltf", "name": "Rock1_17", "scale": 1.1},
	]
	var prop_entries: Array[Dictionary] = []
	for pdef in prop_defs:
		var pdata := _extract_retro_mesh(pdef["scene"], pdef["name"])
		if not pdata.is_empty():
			pdata["scale"] = pdef["scale"]
			pdata["transforms"] = []
			prop_entries.append(pdata)

	var rng := RandomNumberGenerator.new()
	rng.seed = 641996

	# 3. Distribui múltiplas camadas de árvores tropicais nas encostas da pista
	if not tree_entries.is_empty():
		for i in range(4, samples.size() - 4, 2):
			var s := samples[i]
			var cpos: Vector3 = s["pos"]
			var right: Vector3 = s["right"]
			# Duas fileiras de cada lado (beira da estrada + mata fechada no barranco)
			for side: float in [-1.0, 1.0]:
				for layer in 2:
					if layer == 0 and (i % 3 != 0):
						continue
					var out_d := rng.randf_range(3.5, 14.0) if layer == 0 else rng.randf_range(15.0, terrain_skirt_width - 4.0)
					var lat := side * (half_width + curb_width + out_d)
					var y := _jungle_ground_height(s, side, out_d) - 0.35
					var pos := Vector3(cpos.x, y, cpos.z) + right * lat

					# Escolhe uma espécie de árvore (mistura Retro Tree Pack + PSX Forest Level)
					var t_idx := rng.randi_range(0, tree_entries.size() - 1)
					if t_idx == 5 and rng.randf() > 0.25:
						t_idx = 0 # Deixa a árvore seca (índice 5) mais rara na selva tropical
					var entry := tree_entries[t_idx]
					var sc: float = float(entry["scale"]) * rng.randf_range(0.82, 1.38)
					var yaw := rng.randf() * TAU
					var mesh_basis: Basis = entry["basis"]. orthonormalized()
					var final_basis := Basis(Vector3.UP, yaw) * mesh_basis.scaled(Vector3.ONE * sc)
					entry["transforms"].append(Transform3D(final_basis, pos))

	# 4. Distribui rochas, troncos caídos, samambaias/juncos e arbustos perto da margem da pista
	if not prop_entries.is_empty():
		for i in range(3, samples.size() - 3, 2):
			var s := samples[i]
			var cpos: Vector3 = s["pos"]
			var right: Vector3 = s["right"]
			for side: float in [-1.0, 1.0]:
				var out_d := rng.randf_range(1.2, 22.0)
				var lat := side * (half_width + curb_width + out_d)
				var y := _jungle_ground_height(s, side, out_d) - 0.1
				var pos := Vector3(cpos.x, y, cpos.z) + right * lat
				var p_idx := rng.randi_range(0, prop_entries.size() - 1)
				var pentry := prop_entries[p_idx]
				var sc: float = float(pentry["scale"]) * rng.randf_range(0.75, 1.45)
				var yaw := rng.randf() * TAU
				var unit_basis: Basis = pentry["basis"].orthonormalized()
				var final_basis := Basis(Vector3.UP, yaw) * unit_basis.scaled(Vector3.ONE * sc)
				pentry["transforms"].append(Transform3D(final_basis, pos))

	# 5. Cria os MultiMeshInstance3D (apenas 1 draw call por espécie!)
	for entry in tree_entries + prop_entries:
		var xforms: Array = entry["transforms"]
		if xforms.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = entry["mesh"]
		mm.instance_count = xforms.size()
		for k in xforms.size():
			mm.set_instance_transform(k, xforms[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		forest_root.add_child(mmi)
