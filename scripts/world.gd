extends Node3D
## Monta o mundo de teste por código (determinístico: igual para todos os jogadores).
## Um plano grande, uma pista oval demarcada (só visual), cones que voam ao bater,
## rampas, boost pads e cenário low poly.

const PLANE_SIZE := 420.0
const STRAIGHT_X := 40.0 ## retas em x = ±40
const STRAIGHT_LEN := 120.0 ## de z = 0 até z = -120
const TURN_RADIUS := 40.0
const HALF_WIDTH := 8.0
const START_Z := -20.0

const GROUND_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 base_color : source_color = vec3(0.42, 0.68, 0.36);
uniform vec3 line_color : source_color = vec3(0.34, 0.58, 0.3);
uniform float cell = 4.0;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 uv = wpos.xz / cell;
	vec2 g = abs(fract(uv - 0.5) - 0.5) / fwidth(uv);
	float line = 1.0 - min(min(g.x, g.y), 1.0);
	vec2 c = floor(wpos.xz / (cell * 4.0));
	float chk = mod(c.x + c.y, 2.0);
	vec3 col = mix(base_color, base_color * 0.93, chk);
	col = mix(col, line_color, line * 0.85);
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
"""

var _mats := {}


func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_track()
	_build_cones()
	_build_ramps_and_pads()
	_build_scenery()


## Grid de largada na reta da direita, todos virados para -Z (heading 0).
func get_spawn_point(slot: int) -> Dictionary:
	var col := slot % 2
	var row := slot / 2
	var x := STRAIGHT_X + (-3.0 if col == 0 else 3.0)
	var z := START_Z + 5.0 + row * 5.0 + col * 2.0
	return {"pos": Vector3(x, 0.6, z), "heading": 0.0}


# ----------------------------------------------------------------- ambiente

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.55, 0.9)
	sky_mat.sky_horizon_color = Color(0.75, 0.85, 0.95)
	sky_mat.ground_horizon_color = Color(0.75, 0.85, 0.95)
	sky_mat.ground_bottom_color = Color(0.35, 0.45, 0.35)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.85, 0.95)
	env.fog_density = 0.0035
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(-35.0), 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(PLANE_SIZE, 2.0, PLANE_SIZE)
	shape.shape = box
	shape.position.y = -1.0
	body.add_child(shape)

	var mesh := PlaneMesh.new()
	mesh.size = Vector2(PLANE_SIZE, PLANE_SIZE)
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GROUND_SHADER
	mat.shader = sh
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	add_child(body)


# ----------------------------------------------------------------- pista

func _track_centerline() -> PackedVector3Array:
	var pts := PackedVector3Array()
	var step := 5.0
	var n_arc := 36
	# Reta direita (indo para -Z)
	var z := 0.0
	while z > -STRAIGHT_LEN:
		pts.append(Vector3(STRAIGHT_X, 0, z))
		z -= step
	# Curva de cima
	for i in n_arc:
		var a := float(i) / n_arc * PI
		pts.append(Vector3(cos(a) * TURN_RADIUS, 0, -STRAIGHT_LEN - sin(a) * TURN_RADIUS))
	# Reta esquerda (indo para +Z)
	z = -STRAIGHT_LEN
	while z < 0.0:
		pts.append(Vector3(-STRAIGHT_X, 0, z))
		z += step
	# Curva de baixo
	for i in n_arc:
		var a := PI + float(i) / n_arc * PI
		pts.append(Vector3(cos(a) * TURN_RADIUS, 0, -sin(a) * TURN_RADIUS))
	return pts


func _build_track() -> void:
	var pts := _track_centerline()
	var n := pts.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var asphalt := Color(0.27, 0.28, 0.32)
	var curb_a := Color(0.9, 0.15, 0.15)
	var curb_b := Color(0.95, 0.95, 0.95)
	var y := 0.04
	for i in n:
		var p0 := pts[i]
		var p1 := pts[(i + 1) % n]
		var r0 := _right_at(pts, i)
		var r1 := _right_at(pts, (i + 1) % n)
		# Asfalto
		_quad(st, p0 - r0 * HALF_WIDTH, p0 + r0 * HALF_WIDTH, p1 + r1 * HALF_WIDTH, p1 - r1 * HALF_WIDTH, y, asphalt)
		# Zebras
		var c := curb_a if i % 2 == 0 else curb_b
		_quad(st, p0 - r0 * (HALF_WIDTH + 1.0), p0 - r0 * HALF_WIDTH, p1 - r1 * HALF_WIDTH, p1 - r1 * (HALF_WIDTH + 1.0), y, c)
		_quad(st, p0 + r0 * HALF_WIDTH, p0 + r0 * (HALF_WIDTH + 1.0), p1 + r1 * (HALF_WIDTH + 1.0), p1 + r1 * HALF_WIDTH, y, c)
	# Linha de largada quadriculada
	var sq := 1.0
	var cols := int(HALF_WIDTH * 2.0 / sq)
	for row in 2:
		for col in cols:
			var x0 := STRAIGHT_X - HALF_WIDTH + col * sq
			var z0 := START_Z + row * sq
			var cc := Color.WHITE if (row + col) % 2 == 0 else Color(0.08, 0.08, 0.08)
			_quad(st, Vector3(x0, 0, z0 + sq), Vector3(x0 + sq, 0, z0 + sq), Vector3(x0 + sq, 0, z0), Vector3(x0, 0, z0), y + 0.02, cc)

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	var mi := MeshInstance3D.new()
	mi.name = "Track"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _right_at(pts: PackedVector3Array, i: int) -> Vector3:
	var n := pts.size()
	var d := (pts[(i + 1) % n] - pts[(i - 1 + n) % n]).normalized()
	return Vector3(-d.z, 0, d.x)


## a,b,c,d em sentido horário visto de cima (a=esq-trás, b=dir-trás, c=dir-frente, d=esq-frente).
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, y: float, color: Color) -> void:
	a.y = y; b.y = y; c.y = y; d.y = y
	st.set_color(color)
	# Garante que a face aponte para cima independente da ordem.
	var tri_n := (b - a).cross(c - a)
	if tri_n.y > 0.0:
		for v in [a, c, b, a, d, c]:
			st.add_vertex(v)
	else:
		for v in [a, b, c, a, c, d]:
			st.add_vertex(v)


# ----------------------------------------------------------------- cones

func _build_cones() -> void:
	var pts := _track_centerline()
	var n := pts.size()
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.04
	cone_mesh.bottom_radius = 0.32
	cone_mesh.height = 0.8
	cone_mesh.radial_segments = 8
	cone_mesh.rings = 1
	cone_mesh.material = _mat("cone", Color(1.0, 0.45, 0.05))
	var shape := CylinderShape3D.new()
	shape.radius = 0.25
	shape.height = 0.8
	var acc := 0.0
	var spacing := 9.0
	for i in n:
		var seg := pts[(i + 1) % n].distance_to(pts[i])
		acc += seg
		if acc < spacing:
			continue
		acc = 0.0
		var r := _right_at(pts, i)
		for side in [-1.0, 1.0]:
			var cone := RigidBody3D.new()
			cone.collision_layer = 4
			cone.collision_mask = 7
			cone.mass = 0.4
			var cs := CollisionShape3D.new()
			cs.shape = shape
			cone.add_child(cs)
			var mi := MeshInstance3D.new()
			mi.mesh = cone_mesh
			cone.add_child(mi)
			cone.position = pts[i] + r * side * (HALF_WIDTH + 2.0) + Vector3.UP * 0.4
			add_child(cone)


# ----------------------------------------------------------------- rampas e boost

func _build_ramps_and_pads() -> void:
	# Kicker no meio da reta direita
	_ramp(Vector3(STRAIGHT_X, 0, -78), 0.0, Vector3(5, 0.9, 6))
	# Rampa grande no campo interno com boost antes
	_boost_pad(Vector3(0, 0, -30), 0.0)
	_ramp(Vector3(0, 0, -45), 0.0, Vector3(11, 2.6, 8))
	# Rampa enorme fora da pista
	_boost_pad(Vector3(105, 0, -20), 0.0)
	_ramp(Vector3(105, 0, -42), 0.0, Vector3(16, 4.5, 10))
	# Rampas em sequência (pulo-pulo)
	for k in 3:
		_ramp(Vector3(-100, 0, -30 - k * 22), 0.0, Vector3(7, 1.4, 7))
	# Boost pads na pista
	_boost_pad(Vector3(STRAIGHT_X, 0, -55), 0.0)
	_boost_pad(Vector3(-STRAIGHT_X, 0, -60), PI)
	# "Mesa" (tabletop) ao sul
	_ramp(Vector3(0, 0, 80), PI, Vector3(10, 2.0, 10))
	var top := _static_box(Vector3(0, 1.0, 92), Vector3(10, 2.0, 14), _mat("ramp", Color(0.95, 0.72, 0.2)))
	top.name = "Tabletop"
	_ramp(Vector3(0, 0, 104), 0.0, Vector3(10, 2.0, 10))


## Rampa em cunha. heading 0 = sobe indo para -Z.
func _ramp(pos: Vector3, heading: float, size: Vector3) -> void:
	var mesh := PrismMesh.new()
	mesh.left_to_right = 1.0
	mesh.size = size
	mesh.material = _mat("ramp", Color(0.95, 0.72, 0.2))
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_convex_shape()
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	body.transform = Transform3D(Basis(Vector3.UP, heading + PI / 2.0), pos + Vector3.UP * size.y * 0.5)
	add_child(body)


func _boost_pad(pos: Vector3, heading: float) -> void:
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitorable = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 1.5, 5)
	cs.shape = box
	cs.position.y = 0.75
	area.add_child(cs)

	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.55, 0.1)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.45, 0.05)
	glow.emission_energy_multiplier = 1.5
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(4, 0.06, 5)
	bm.material = _mat("pad_base", Color(0.2, 0.2, 0.25))
	base.mesh = bm
	base.position.y = 0.05
	area.add_child(base)
	# Setas ">" apontando para frente (-Z local)
	var arrow_mesh := BoxMesh.new()
	arrow_mesh.size = Vector3(0.35, 0.05, 2.0)
	arrow_mesh.material = glow
	for k in 2:
		for s in [-1.0, 1.0]:
			var a := MeshInstance3D.new()
			a.mesh = arrow_mesh
			a.position = Vector3(s * 0.62, 0.1, 1.2 - k * 2.0)
			a.rotation.y = s * deg_to_rad(40.0)
			area.add_child(a)
	area.transform = Transform3D(Basis(Vector3.UP, heading), pos)
	area.body_entered.connect(_on_boost_body_entered)
	add_child(area)


func _on_boost_body_entered(body: Node3D) -> void:
	if body.has_meta("kart"):
		var k: Kart = body.get_meta("kart")
		if k.is_local():
			k.apply_boost(1.1)


# ----------------------------------------------------------------- cenário

func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.25
	trunk_mesh.bottom_radius = 0.35
	trunk_mesh.height = 2.0
	trunk_mesh.radial_segments = 6
	trunk_mesh.rings = 1
	trunk_mesh.material = _mat("trunk", Color(0.45, 0.3, 0.2))
	var leaf_mesh := CylinderMesh.new()
	leaf_mesh.top_radius = 0.0
	leaf_mesh.bottom_radius = 1.8
	leaf_mesh.height = 4.0
	leaf_mesh.radial_segments = 6
	leaf_mesh.rings = 1
	leaf_mesh.material = _mat("leaf", Color(0.2, 0.55, 0.3))
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 1.0
	rock_mesh.height = 1.6
	rock_mesh.radial_segments = 6
	rock_mesh.rings = 3
	rock_mesh.material = _mat("rock", Color(0.55, 0.55, 0.58))
	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = 0.35
	trunk_shape.height = 2.0

	var placed := 0
	var tries := 0
	while placed < 120 and tries < 2000:
		tries += 1
		var p := Vector3(rng.randf_range(-190, 190), 0, rng.randf_range(-190, 190))
		if not _is_free_for_scenery(p):
			continue
		placed += 1
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.position = p
		body.rotation.y = rng.randf() * TAU
		var sc := rng.randf_range(0.8, 1.6)
		if rng.randf() < 0.75:
			var t := MeshInstance3D.new()
			t.mesh = trunk_mesh
			t.position.y = 1.0
			body.add_child(t)
			var l := MeshInstance3D.new()
			l.mesh = leaf_mesh
			l.position.y = 2.0 + 2.0 * sc
			l.scale = Vector3.ONE * sc
			body.add_child(l)
			var cs := CollisionShape3D.new()
			cs.shape = trunk_shape
			cs.position.y = 1.0
			body.add_child(cs)
		else:
			var r := MeshInstance3D.new()
			r.mesh = rock_mesh
			r.scale = Vector3(sc * 1.3, sc, sc)
			r.position.y = 0.2
			body.add_child(r)
			var cs2 := CollisionShape3D.new()
			var ss := SphereShape3D.new()
			ss.radius = sc
			cs2.shape = ss
			cs2.position.y = 0.2
			body.add_child(cs2)
		add_child(body)


func _is_free_for_scenery(p: Vector3) -> bool:
	# Fora da área da pista oval (com folga)
	if absf(p.x) < STRAIGHT_X + HALF_WIDTH + 14.0 and p.z < TURN_RADIUS + 20.0 and p.z > -STRAIGHT_LEN - TURN_RADIUS - 20.0:
		return false
	# Longe das rampas e áreas de manobra
	for c in [Vector3(105, 0, -35), Vector3(-100, 0, -52), Vector3(0, 0, 92)]:
		if p.distance_to(c) < 28.0:
			return false
	return true


func _static_box(pos: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	body.position = pos
	add_child(body)
	return body


func _mat(key: String, color: Color) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.85
		_mats[key] = m
	return _mats[key]
