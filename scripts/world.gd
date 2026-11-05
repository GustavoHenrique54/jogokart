extends Node3D
## Pista de descida de morro (Touge / Ladeira de Rolimã + Pumptrack).
##
## Segue exatamente o traçado visto de cima enviado pelo usuário, escalado para
## ~4.2 km de extensão (~3 minutos de descida intensa), com:
## - Declives e aclives irregulares tanto no sentido da pista quanto de um lado
##   ao outro da rua (bolsões de impulso em verde/azul vs lombadas/aclives em
##   amarelo/laranja que fazem o carrinho saltar e perder um pouco de velocidade).
## - Guard-rails laterais (zebras elevadas) para manter a disputa dentro da rua.
## - Minimapa/progresso sincronizado e linha de chegada lá embaixo no pé do morro.

const HALF_WIDTH := 10.5 ## Rua de 21m de largura para permitir escolher lados (esq/centro/dir)
const CURB_WIDTH := 1.1
const CURB_HEIGHT := 0.85
const CROSS_SLICES := 10 ## subdivisões na largura da rua para criar bolsões laterais de declive
const SAMPLE_STEP := 2.8 ## metros entre anéis da malha da pista

## Pontos de controle (X, Z) fiéis ao desenho de "caminho da pista (vista de cima)".
## Cada unidade equivale a ~11 metros no mundo, totalizando ~4.250 metros de descida.
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
const BASE_SLOPE := 0.088 ## ~8.8% de inclinação média (~375 m de desnível do topo ao fim)

var samples: Array[Dictionary] = []
var total_length := 0.0


func _ready() -> void:
	_build_environment()
	_generate_centerline()
	_build_track_chunks()
	_build_start_and_finish_banners()
	_build_scenery()


func get_spawn_point(slot: int) -> Dictionary:
	if samples.size() < 6:
		return {"pos": Vector3.ZERO, "heading": 0.0}
	var col := slot % 3
	var row := slot / 3
	var idx := clampi(4 - row, 1, 6)
	var s := samples[idx]
	var lateral := (col - 1) * 3.2
	var p: Vector3 = s["pos"] + s["right"] * lateral
	p.y = _surface_height(s["dist"], lateral, s["pos"].y) + 0.85
	var f: Vector3 = s["fwd"]
	var heading := atan2(-f.x, -f.z)
	return {"pos": p, "heading": heading}


## Progresso de 0.0 (largada) a 1.0 (chegada) para o HUD e placar.
func compute_progress(world_pos: Vector3) -> float:
	if samples.is_empty() or total_length <= 1.0:
		return 0.0
	var best_d2 := INF
	var best_dist := 0.0
	# Busca amostrada rápida a cada 4 pontos e refina vizinhança
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


# ----------------------------------------------------------------- ambiente

func _build_environment() -> void:
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
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-32.0), 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 95.0
	add_child(sun)


# ----------------------------------------------------------------- geometria da ladeira + pumptrack

func _generate_centerline() -> void:
	var curve := Curve3D.new()
	curve.bake_interval = SAMPLE_STEP
	var n := CONTROL_POINTS_2D.size()
	for i in n:
		var p2: Vector2 = CONTROL_POINTS_2D[i] * WORLD_SCALE
		var p := Vector3(p2.x, 0.0, p2.y)
		var prev2: Vector2 = CONTROL_POINTS_2D[maxi(0, i - 1)] * WORLD_SCALE
		var next2: Vector2 = CONTROL_POINTS_2D[mini(n - 1, i + 1)] * WORLD_SCALE
		var tangent := Vector3(next2.x - prev2.x, 0.0, next2.y - prev2.y) * 0.28
		curve.add_point(p, -tangent, tangent)

	var baked := curve.get_baked_points()
	samples.clear()
	var dist := 0.0
	for i in baked.size():
		if i > 0:
			dist += baked[i].distance_to(baked[i - 1])
		var prev_p := baked[maxi(0, i - 1)]
		var next_p := baked[mini(baked.size() - 1, i + 1)]
		var fwd := (next_p - prev_p)
		fwd.y = 0.0
		fwd = fwd.normalized()
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		var base_y := -dist * BASE_SLOPE
		samples.append({
			"pos": Vector3(baked[i].x, base_y, baked[i].z),
			"fwd": fwd,
			"right": right,
			"dist": dist,
		})
	total_length = dist


## Retorna a altura exata da rua na distância `d` (metros desde a largada) e posição
## lateral `lat` (-HALF_WIDTH a +HALF_WIDTH). Combina a descida contínua do morro com
## ondas de pumptrack assimétricas (um lado da rua desce mais que o outro, alternando).
func _surface_height(d: float, lat: float, base_y: float) -> float:
	# Suaviza nos primeiros 30m (largada) e últimos 35m (chegada)
	var env := smoothstep(12.0, 42.0, d) * (1.0 - smoothstep(total_length - 45.0, total_length - 12.0, d))
	if env <= 0.001:
		return base_y

	var u := clampf(lat / HALF_WIDTH, -1.0, 1.0) # -1 = esquerda, 0 = centro, +1 = direita

	# 1. Ondulação principal da rua (declives fortes seguidos de aclives curtos)
	var center_wave := sin(d * 0.075) * 1.45 + sin(d * 0.16 + 1.1) * 0.75

	# 2. Bolsões assimétricos nas laterais (às vezes a esquerda afunda em um declive ótimo
	#    enquanto a direita sobe numa lombada, e vice-versa ao longo da descida)
	var side_tilt := (sin(d * 0.095 + 0.4) * 1.65 + cos(d * 0.185 - 0.8) * 1.05) * u

	# 3. Calhas no meio ou nas bordas (u² - 0.5 diferencia centro vs cantos da pista)
	var channel_wave := sin(d * 0.13 + 2.2) * (u * u - 0.45) * 1.55

	# 4. Lombadas súbitas (cristas de pumptrack) em pontos específicos da seção transversal
	var bump_phase := sin(d * 0.22 + u * 1.7)
	var sharp_crest := pow(maxf(0.0, bump_phase), 3.0) * 1.35

	return base_y + (center_wave + side_tilt + channel_wave + sharp_crest) * env


func _build_track_chunks() -> void:
	var road_mat := StandardMaterial3D.new()
	road_mat.vertex_color_use_as_albedo = true
	road_mat.roughness = 0.88

	# Divide a pista em blocos de 140 anéis para culling eficiente no navegador e Jolt Physics
	var chunk_size := 140
	var num_samples := samples.size()
	var start_idx := 0
	while start_idx < num_samples - 1:
		var end_idx := mini(start_idx + chunk_size, num_samples - 1)
		_build_single_chunk(start_idx, end_idx, road_mat)
		start_idx = end_idx


func _build_single_chunk(i_start: int, i_end: int, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Pré-calcula os vértices de cada anel (de i_start a i_end)
	var rings: Array = []
	for i in range(i_start, i_end + 1):
		var s := samples[i]
		var d: float = s["dist"]
		var cpos: Vector3 = s["pos"]
		var right: Vector3 = s["right"]
		var ring_pts: Array[Vector3] = []
		for j in range(CROSS_SLICES + 1):
			var frac := float(j) / float(CROSS_SLICES) # 0..1
			var lat := lerpf(-HALF_WIDTH, HALF_WIDTH, frac)
			var y := _surface_height(d, lat, cpos.y)
			ring_pts.append(Vector3(cpos.x, y, cpos.z) + right * lat)
		rings.append(ring_pts)

	for r in range(rings.size() - 1):
		var i := i_start + r
		var d0: float = samples[i]["dist"]
		var d1: float = samples[i + 1]["dist"]
		var row0: Array[Vector3] = rings[r]
		var row1: Array[Vector3] = rings[r + 1]

		# Superfície da rua com leitura visual do relevo (declive vs aclive)
		for j in range(CROSS_SLICES):
			var p00 := row0[j]
			var p01 := row0[j + 1]
			var p10 := row1[j]
			var p11 := row1[j + 1]

			# Inclinação longitudinal deste quadrado da rua:
			var avg_y0 := (p00.y + p01.y) * 0.5
			var avg_y1 := (p10.y + p11.y) * 0.5
			var local_drop := (avg_y0 - avg_y1) / maxf(d1 - d0, 0.01) # > BASE_SLOPE = descida mais forte!
			var delta_slope := local_drop - BASE_SLOPE

			var col := _slope_color(delta_slope, j, i)
			_add_quad(st, p00, p01, p11, p10, col)

		# Guard-rails / zebras elevadas nas duas bordas para segurar o rolimã na pista
		var curb_col := Color(0.92, 0.2, 0.18) if (i / 2) % 2 == 0 else Color(0.95, 0.95, 0.95)
		var r0: Vector3 = samples[i]["right"]
		var r1: Vector3 = samples[i + 1]["right"]

		# Parede esquerda
		var l_in0 := row0[0]
		var l_in1 := row1[0]
		var l_top0 := l_in0 - r0 * (CURB_WIDTH * 0.3) + Vector3.UP * CURB_HEIGHT
		var l_top1 := l_in1 - r1 * (CURB_WIDTH * 0.3) + Vector3.UP * CURB_HEIGHT
		var l_out0 := l_in0 - r0 * CURB_WIDTH + Vector3.UP * CURB_HEIGHT
		var l_out1 := l_in1 - r1 * CURB_WIDTH + Vector3.UP * CURB_HEIGHT
		_add_quad(st, l_top0, l_in0, l_in1, l_top1, curb_col)
		_add_quad(st, l_out0, l_top0, l_top1, l_out1, curb_col.darkened(0.15))

		# Parede direita
		var r_in0 := row0[CROSS_SLICES]
		var r_in1 := row1[CROSS_SLICES]
		var r_top0 := r_in0 + r0 * (CURB_WIDTH * 0.3) + Vector3.UP * CURB_HEIGHT
		var r_top1 := r_in1 + r1 * (CURB_WIDTH * 0.3) + Vector3.UP * CURB_HEIGHT
		var r_out0 := r_in0 + r0 * CURB_WIDTH + Vector3.UP * CURB_HEIGHT
		var r_out1 := r_in1 + r1 * CURB_WIDTH + Vector3.UP * CURB_HEIGHT
		_add_quad(st, r_in0, r_top0, r_top1, r_in1, curb_col)
		_add_quad(st, r_top0, r_out0, r_out1, r_top1, curb_col.darkened(0.15))

	st.generate_normals()
	var mesh := st.commit()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


## Colore o asfalto sutilmente para que o jogador consiga "ler" onde a rua afunda (declive)
## e onde ela sobe num aclive/lombada:
## - Asfalto padrão: cinza escuro
## - Declive forte (onde ganha velocidade): puxa para azul-petróleo / ciano vibrante nas faixas
## - Aclive / crista (onde salta e perde embalo): puxa para âmbar / terracota claro
func _slope_color(delta_slope: float, slice_j: int, ring_i: int) -> Color:
	var base := Color(0.25, 0.27, 0.31)
	if (ring_i / 3) % 2 == 0 and (slice_j == 0 or slice_j == CROSS_SLICES - 1):
		base = base.lightened(0.05)
	# Faixa central tracejada da rua
	if slice_j == CROSS_SLICES / 2 and (ring_i % 6 < 3):
		base = Color(0.82, 0.78, 0.32)

	if delta_slope > 0.025:
		# Declive forte: bolsão de velocidade!
		var t := clampf((delta_slope - 0.025) / 0.14, 0.0, 1.0)
		return base.lerp(Color(0.12, 0.68, 0.88), t * 0.78)
	elif delta_slope < -0.03:
		# Aclive / lombada: risco de salto!
		var t := clampf((-delta_slope - 0.03) / 0.14, 0.0, 1.0)
		return base.lerp(Color(0.92, 0.48, 0.18), t * 0.78)
	return base


func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	st.set_color(col)
	# Em Godot + Jolt Physics, a face frontal (normal para cima/dentro da pista) precisa
	# de produto vetorial (v1 - v0).cross(v2 - v0) apontando na direção esperada, e também
	# habilitamos backface_collision na ConcavePolygonShape3D para segurança total.
	for v in [a, c, b, a, d, c]:
		st.add_vertex(v)


# ----------------------------------------------------------------- largada, chegada e cenário

func _build_start_and_finish_banners() -> void:
	if samples.size() < 20:
		return
	_build_arch(samples[6], Color(0.2, 0.75, 0.35), "LARGADA — DESÇA O MORRO!")
	var finish_sample := samples[samples.size() - 8]
	_build_arch(finish_sample, Color(0.95, 0.75, 0.15), "CHEGADA!")

	# Área detectora da linha de chegada
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(HALF_WIDTH * 2.2, 8.0, 4.0)
	cs.shape = box
	area.add_child(cs)
	var f: Vector3 = finish_sample["fwd"]
	var heading := atan2(-f.x, -f.z)
	area.transform = Transform3D(Basis(Vector3.UP, heading), finish_sample["pos"] + Vector3.UP * 3.0)
	area.body_entered.connect(_on_finish_entered)
	add_child(area)


func _build_arch(s: Dictionary, banner_color: Color, label_text: String) -> void:
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
		p.position = Vector3(side * (HALF_WIDTH + 0.5), 3.5, 0.0)
		root.add_child(p)

	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = banner_color
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(HALF_WIDTH * 2.2, 1.3, 0.5)
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
	add_child(root)


func _on_finish_entered(body: Node3D) -> void:
	if body.has_meta("kart"):
		var k: Kart = body.get_meta("kart")
		if k.finished_time <= 0.0 and k.race_time > 10.0:
			k.finished_time = k.race_time


func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.45, 0.3, 0.18)
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.2, 0.56, 0.28)

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.25
	trunk_mesh.bottom_radius = 0.38
	trunk_mesh.height = 2.6
	trunk_mesh.radial_segments = 6
	trunk_mesh.material = trunk_mat

	var leaf_mesh := CylinderMesh.new()
	leaf_mesh.top_radius = 0.0
	leaf_mesh.bottom_radius = 2.2
	leaf_mesh.height = 5.2
	leaf_mesh.radial_segments = 6
	leaf_mesh.material = leaf_mat

	# Placas de curva ("chevron") e pinheiros ao longo da descida da serra
	for i in range(10, samples.size() - 10, 9):
		var s := samples[i]
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var dist_out := HALF_WIDTH + rng.randf_range(4.0, 14.0)
		var pos: Vector3 = s["pos"] + s["right"] * (side * dist_out)
		var tree := Node3D.new()
		var sc := rng.randf_range(0.85, 1.55)
		tree.position = pos + Vector3.UP * -0.4
		var t := MeshInstance3D.new()
		t.mesh = trunk_mesh
		t.position.y = 1.3
		tree.add_child(t)
		var l := MeshInstance3D.new()
		l.mesh = leaf_mesh
		l.position.y = 2.6 + 2.2 * sc
		l.scale = Vector3.ONE * sc
		tree.add_child(l)
		add_child(tree)
