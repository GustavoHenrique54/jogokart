class_name TrapLog
extends Node3D
## Tora de Arapuca da Habilidade 1 [Q] do Curupira.
## Permanece na pista por até 5.0 segundos como um obstáculo fixo.
## Ao colidir com um kart rival: causa impacto violento (perde 45% da velocidade atual,
## é jogado para o lado e tem o alinhamento das rodas desestabilizado por 1.5s).
## A tora se despedaça após o primeiro impacto.

const LIFETIME := 5.0
const COLLISION_RADIUS := 1.7

var caster_peer_id: int = -1
var _elapsed := 0.0
var _shattered := false

var _log_mesh: MeshInstance3D
var _splinter_particles: CPUParticles3D
var _dust_particles: CPUParticles3D


func _ready() -> void:
	top_level = true
	_build_visuals()


func setup(spawn_pos: Vector3, spawn_rot_y: float, caster_id: int) -> void:
	if is_inside_tree():
		global_position = spawn_pos
		rotation.y = spawn_rot_y + deg_to_rad(randf_range(-15.0, 15.0))
	else:
		position = spawn_pos
		rotation.y = spawn_rot_y
	caster_peer_id = caster_id


func _build_visuals() -> void:
	# Material da casca da madeira
	var mat_bark := StandardMaterial3D.new()
	mat_bark.albedo_color = Color(0.32, 0.19, 0.09)
	mat_bark.roughness = 0.9

	# Tora de madeira transversal na pista
	_log_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.28
	cyl.bottom_radius = 0.30
	cyl.height = 2.4
	cyl.radial_segments = 12
	_log_mesh.mesh = cyl
	_log_mesh.material_override = mat_bark
	_log_mesh.rotation = Vector3(0, 0, deg_to_rad(90.0))
	_log_mesh.position = Vector3(0, 0.22, 0)
	add_child(_log_mesh)

	# Cipós / Folhagens amarradas na tora
	var mat_vine := StandardMaterial3D.new()
	mat_vine.albedo_color = Color(0.18, 0.65, 0.22)
	mat_vine.roughness = 0.6
	for vx in [-0.6, 0.0, 0.6]:
		var vine := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.28
		tm.outer_radius = 0.35
		tm.rings = 10
		tm.ring_segments = 5
		vine.mesh = tm
		vine.material_override = mat_vine
		vine.position = Vector3(vx, 0.22, 0)
		vine.rotation = Vector3(deg_to_rad(90.0), 0, 0)
		add_child(vine)

	# Partículas de lascas e estilhaços de madeira
	_splinter_particles = CPUParticles3D.new()
	var part_mat := StandardMaterial3D.new()
	part_mat.albedo_color = Color(0.55, 0.38, 0.2)
	part_mat.roughness = 0.95
	var p_box := BoxMesh.new()
	p_box.size = Vector3(0.12, 0.12, 0.28)
	_splinter_particles.mesh = p_box
	_splinter_particles.material_override = part_mat
	_splinter_particles.emitting = false
	_splinter_particles.one_shot = true
	_splinter_particles.amount = 32
	_splinter_particles.lifetime = 0.65
	_splinter_particles.explosiveness = 0.95
	_splinter_particles.direction = Vector3(0, 1, 0)
	_splinter_particles.spread = 75.0
	_splinter_particles.initial_velocity_min = 5.0
	_splinter_particles.initial_velocity_max = 12.0
	_splinter_particles.gravity = Vector3(0, -18.0, 0)
	_splinter_particles.position = Vector3(0, 0.25, 0)
	add_child(_splinter_particles)

	# Poeira do impacto
	_dust_particles = CPUParticles3D.new()
	var d_mat := StandardMaterial3D.new()
	d_mat.albedo_color = Color(0.75, 0.68, 0.55, 0.7)
	d_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var d_sph := SphereMesh.new()
	d_sph.radius = 0.25
	d_sph.height = 0.5
	_dust_particles.mesh = d_sph
	_dust_particles.material_override = d_mat
	_dust_particles.emitting = false
	_dust_particles.one_shot = true
	_dust_particles.amount = 18
	_dust_particles.lifetime = 0.7
	_dust_particles.explosiveness = 0.9
	_dust_particles.direction = Vector3(0, 0.8, 0)
	_dust_particles.spread = 80.0
	_dust_particles.initial_velocity_min = 2.0
	_dust_particles.initial_velocity_max = 5.5
	_dust_particles.gravity = Vector3(0, 1.0, 0)
	_dust_particles.position = Vector3(0, 0.15, 0)
	add_child(_dust_particles)


func _physics_process(delta: float) -> void:
	if _shattered:
		return

	_elapsed += delta
	if _elapsed >= LIFETIME:
		_shatter(null)
		return

	# Checa colisão com karts na pista
	for node in get_tree().get_nodes_in_group("karts"):
		if not (node is Kart):
			continue
		var kart := node as Kart

		# Conjurador imune por 0.5s para não colidir consigo mesmo ao soltar
		if kart.peer_id == caster_peer_id and _elapsed < 0.5:
			continue

		var dist := global_position.distance_to(kart.ball.global_position)
		if dist <= COLLISION_RADIUS:
			_shatter(kart)
			return


func _shatter(target_kart: Kart) -> void:
	if _shattered:
		return
	_shattered = true

	if target_kart != null:
		target_kart.apply_trap_log_hit(global_position)

	# Efeito visual de despedaçamento
	_log_mesh.visible = false
	for child in get_children():
		if child is MeshInstance3D:
			child.visible = false

	_splinter_particles.emitting = true
	_dust_particles.emitting = true

	var t := create_tween()
	t.tween_interval(0.7)
	t.tween_callback(queue_free)

