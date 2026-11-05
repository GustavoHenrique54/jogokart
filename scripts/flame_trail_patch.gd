class_name FlameTrailPatch
extends Node3D
## Trilha de fogo incandescente deixada pelo Boitatá no asfalto com a habilidade "Rastro Flamejante".
## Permanece ativa por 3.5 segundos. Qualquer oponente que passar por cima sofre superaquecimento nas rodas,
## perde 35% de velocidade e patina levemente.

var caster_peer_id: int = -1
var lifetime: float = 3.5
var _elapsed: float = 0.0
var _hit_peers: Dictionary = {}

var _flame_mesh: MeshInstance3D
var _light: OmniLight3D
var _particles: CPUParticles3D
var _area: Area3D


func _ready() -> void:
	_build_visuals()
	_build_collider()


func setup(pos: Vector3, caster_id: int) -> void:
	if is_inside_tree():
		global_position = pos
	else:
		position = pos
	caster_peer_id = caster_id


func _build_visuals() -> void:
	# Material de fogo vivo
	var mat_fire := StandardMaterial3D.new()
	mat_fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_fire.albedo_color = Color(1.0, 0.38, 0.05)

	# Labareda poligonal no chão
	_flame_mesh = MeshInstance3D.new()
	var prism := BoxMesh.new()
	prism.size = Vector3(0.55, 0.45, 0.55)
	prism.material = mat_fire
	_flame_mesh.mesh = prism
	_flame_mesh.position = Vector3(0, 0.2, 0)
	add_child(_flame_mesh)

	# Luz da labareda
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.5, 0.1)
	_light.light_energy = 2.2
	_light.omni_range = 3.2
	_light.position = Vector3(0, 0.3, 0)
	add_child(_light)

	# Fagulhas e brasas subindo do chão
	_particles = CPUParticles3D.new()
	var part_mat := StandardMaterial3D.new()
	part_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	part_mat.vertex_color_use_as_albedo = true
	var p_mesh := BoxMesh.new()
	p_mesh.size = Vector3(0.08, 0.08, 0.08)
	p_mesh.material = part_mat
	_particles.mesh = p_mesh
	_particles.amount = 14
	_particles.lifetime = 0.5
	_particles.direction = Vector3(0, 1, 0)
	_particles.spread = 35.0
	_particles.initial_velocity_min = 1.0
	_particles.initial_velocity_max = 2.8
	_particles.gravity = Vector3(0, 3.0, 0)
	_particles.color = Color(1.0, 0.75, 0.2)
	_particles.position = Vector3(0, 0.1, 0)
	add_child(_particles)


func _build_collider() -> void:
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 1 | 2
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.95
	cyl.height = 1.0
	col.shape = cyl
	col.position = Vector3(0, 0.5, 0)
	_area.add_child(col)
	add_child(_area)
	_area.body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	var time_left: float = lifetime - _elapsed

	# Animação oscilante do fogo
	if _flame_mesh:
		var flicker: float = 1.0 + 0.15 * sin(_elapsed * 24.0)
		_flame_mesh.scale = Vector3(flicker, flicker * 1.1, flicker)
		_flame_mesh.rotate_y(delta * 2.5)

	# Verificação de proximidade com karts
	for kart in get_tree().get_nodes_in_group("karts"):
		if not is_instance_valid(kart) or not (kart is Kart):
			continue
		if kart.peer_id == caster_peer_id:
			continue
		if _hit_peers.has(kart.peer_id):
			continue

		var dist: float = global_position.distance_to(kart.ball.global_position)
		if dist <= 1.25:
			_hit_peers[kart.peer_id] = true
			kart.apply_flame_trail_hit(global_position)

	# Apaga suavemente entre 3 e 3.5 segundos
	if time_left <= 0.6:
		var fade: float = clampf(time_left / 0.6, 0.0, 1.0)
		scale = Vector3(fade, fade, fade)
		if _light:
			_light.light_energy = 2.2 * fade

	if _elapsed >= lifetime:
		queue_free()


func _on_body_entered(body: Node) -> void:
	var kart: Kart = body.get_meta("kart", null)
	if kart and is_instance_valid(kart):
		if kart.peer_id != caster_peer_id and not _hit_peers.has(kart.peer_id):
			_hit_peers[kart.peer_id] = true
			kart.apply_flame_trail_hit(global_position)
