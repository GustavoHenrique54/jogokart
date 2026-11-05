class_name AbductionBeam
extends Node3D
## Feixe cilíndrico de abdução da Ultimate do ET de Varginha: "Abdução Espacial (Luz de Nave)".
## Projeta um holofote cilíndrico de luz azulada que varre uma área da pista à frente por 3.5 segundos.
## Leva 0.5s para atingir o solo após ativação (permitindo esquiva).
## Rivais pegos são suspensos a 1m por 1.8s sem direção nem embalo.
## O ET recebe bônus violento de aceleração contínua (túnel de vácuo alienígena).

const DELAY_TO_GROUND := 0.5
const ACTIVE_DURATION := 3.5
const SWEEP_SPEED := 9.0
const CORE_RADIUS := 4.2
const EDGE_RADIUS := 5.8
const BEAM_HEIGHT := 32.0

var caster_peer_id: int = -1
var sweep_direction := Vector3.FORWARD
var _elapsed := 0.0
var _is_active := false
var _is_fading := false

var _outer_cylinder: MeshInstance3D
var _inner_cylinder: MeshInstance3D
var _ground_ring: MeshInstance3D
var _ground_disc: MeshInstance3D
var _light: OmniLight3D
var _particles: CPUParticles3D
var _mat_beam: StandardMaterial3D
var _mat_core: StandardMaterial3D


func _ready() -> void:
	top_level = true
	_build_visuals()


func setup(spawn_pos: Vector3, dir: Vector3, caster_id: int) -> void:
	if is_inside_tree():
		global_position = spawn_pos
	else:
		position = spawn_pos
	sweep_direction = Vector3(dir.x, 0.0, dir.z).normalized()
	if sweep_direction.is_zero_approx():
		sweep_direction = Vector3.FORWARD
	caster_peer_id = caster_id


func _build_visuals() -> void:
	# Material translúcido do cilindro externo
	_mat_beam = StandardMaterial3D.new()
	_mat_beam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_beam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_beam.albedo_color = Color(0.25, 0.78, 1.0, 0.28)
	_mat_beam.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Material translúcido do núcleo brilhante
	_mat_core = StandardMaterial3D.new()
	_mat_core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_core.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_core.albedo_color = Color(0.65, 0.95, 1.0, 0.52)
	_mat_core.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Cilindro externo
	_outer_cylinder = MeshInstance3D.new()
	var cyl_mesh := CylinderMesh.new()
	cyl_mesh.top_radius = CORE_RADIUS * 1.08
	cyl_mesh.bottom_radius = CORE_RADIUS
	cyl_mesh.height = BEAM_HEIGHT
	cyl_mesh.radial_segments = 24
	cyl_mesh.rings = 2
	_outer_cylinder.mesh = cyl_mesh
	_outer_cylinder.material_override = _mat_beam
	_outer_cylinder.position = Vector3(0, BEAM_HEIGHT * 0.5, 0)
	add_child(_outer_cylinder)

	# Núcleo cilíndrico interno
	_inner_cylinder = MeshInstance3D.new()
	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = CORE_RADIUS * 0.45
	core_mesh.bottom_radius = CORE_RADIUS * 0.4
	core_mesh.height = BEAM_HEIGHT
	core_mesh.radial_segments = 16
	core_mesh.rings = 2
	_inner_cylinder.mesh = core_mesh
	_inner_cylinder.material_override = _mat_core
	_inner_cylinder.position = Vector3(0, BEAM_HEIGHT * 0.5, 0)
	add_child(_inner_cylinder)

	# Anel de advertência e projeção no solo
	_ground_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = CORE_RADIUS - 0.18
	ring_mesh.outer_radius = CORE_RADIUS + 0.18
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 6
	_ground_ring.mesh = ring_mesh
	_ground_ring.material_override = _mat_core
	_ground_ring.position = Vector3(0, 0.12, 0)
	add_child(_ground_ring)

	# Disco de solo suave
	_ground_disc = MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = CORE_RADIUS * 0.95
	disc_mesh.bottom_radius = CORE_RADIUS * 0.95
	disc_mesh.height = 0.05
	disc_mesh.radial_segments = 20
	_ground_disc.mesh = disc_mesh
	_ground_disc.material_override = _mat_beam
	_ground_disc.position = Vector3(0, 0.08, 0)
	add_child(_ground_disc)

	# Luz do feixe
	_light = OmniLight3D.new()
	_light.light_color = Color(0.3, 0.85, 1.0)
	_light.light_energy = 1.5
	_light.omni_range = 14.0
	_light.position = Vector3(0, 2.5, 0)
	add_child(_light)

	# Partículas de plasma e poeira cósmica ascendentes
	_particles = CPUParticles3D.new()
	var p_mat := StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.vertex_color_use_as_albedo = true
	var p_box := BoxMesh.new()
	p_box.size = Vector3(0.12, 0.12, 0.12)
	_particles.mesh = p_box
	_particles.material_override = p_mat
	_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_particles.emission_ring_radius = CORE_RADIUS * 0.75
	_particles.emission_ring_inner_radius = 0.4
	_particles.emission_ring_height = 0.5
	_particles.amount = 38
	_particles.lifetime = 1.4
	_particles.direction = Vector3(0, 1, 0)
	_particles.spread = 8.0
	_particles.initial_velocity_min = 6.0
	_particles.initial_velocity_max = 14.0
	_particles.color = Color(0.4, 0.9, 1.0, 0.85)
	_particles.position = Vector3(0, 0.2, 0)
	add_child(_particles)

	# Começa com intensidade de descida (aviso de 0.5s)
	_outer_cylinder.scale = Vector3(0.2, 1.0, 0.2)
	_inner_cylinder.scale = Vector3(0.2, 1.0, 0.2)
	_ground_ring.scale = Vector3(0.2, 1.0, 0.2)
	_ground_disc.scale = Vector3(0.2, 1.0, 0.2)


func _physics_process(delta: float) -> void:
	if _is_fading:
		return

	_elapsed += delta

	# Efeito de pulso e rotação dos anéis cósmicos
	_outer_cylinder.rotate_y(delta * 1.8)
	_inner_cylinder.rotate_y(-delta * 2.6)
	_ground_ring.rotate_y(delta * 3.2)

	if _elapsed < DELAY_TO_GROUND:
		# Fase de descida do feixe (0.5s de advertência para permitir esquiva)
		var progress := _elapsed / DELAY_TO_GROUND
		var s := lerpf(0.2, 1.0, progress)
		_outer_cylinder.scale = Vector3(s, 1.0, s)
		_inner_cylinder.scale = Vector3(s, 1.0, s)
		_ground_ring.scale = Vector3(s, 1.0, s)
		_ground_disc.scale = Vector3(s, 1.0, s)
		_light.light_energy = lerpf(1.5, 6.0, progress)
		return

	# Feixe totalmente ativo na pista
	if not _is_active:
		_is_active = true
		_outer_cylinder.scale = Vector3.ONE
		_inner_cylinder.scale = Vector3.ONE
		_ground_ring.scale = Vector3.ONE
		_ground_disc.scale = Vector3.ONE
		_light.light_energy = 6.0

	var active_time := _elapsed - DELAY_TO_GROUND
	if active_time >= ACTIVE_DURATION:
		_fade_out()
		return

	# O holofote cilíndrico varre a pista à frente
	global_position += sweep_direction * SWEEP_SPEED * delta

	# Pulso suave de luz
	var pulse := 1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.015)
	_ground_ring.scale = Vector3(pulse, 1.0, pulse)

	# Interação com os karts na pista
	for node in get_tree().get_nodes_in_group("karts"):
		if not (node is Kart):
			continue
		var kart := node as Kart

		# Se for o próprio ET que conjurou: concede o túnel de vácuo violento
		if kart.peer_id == caster_peer_id:
			kart.abduction_vacuum_time_left = maxf(kart.abduction_vacuum_time_left, 0.25)
			continue

		var kpos := kart.ball.global_position
		var xz_dist := Vector2(kpos.x - global_position.x, kpos.z - global_position.z).length()
		var y_dist := absf(kpos.y - global_position.y)

		if y_dist > 18.0:
			continue

		if xz_dist <= CORE_RADIUS:
			# Levitação total dos Rivais: suspensos a 1m do solo por 1.8s
			kart.apply_abduction_lift(1.8)
		elif xz_dist <= EDGE_RADIUS:
			# Beirada do feixe: perde tração e derrapa levemente
			kart.apply_abduction_edge_traction_loss()


func _fade_out() -> void:
	_is_fading = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_light, "light_energy", 0.0, 0.45)
	tween.tween_property(_mat_beam, "albedo_color:a", 0.0, 0.45)
	tween.tween_property(_mat_core, "albedo_color:a", 0.0, 0.45)
	tween.tween_property(_ground_ring, "scale", Vector3(0.01, 1.0, 0.01), 0.45)
	tween.chain().tween_callback(queue_free)
