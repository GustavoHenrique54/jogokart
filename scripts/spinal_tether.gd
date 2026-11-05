class_name SpinalTether
extends Node3D
## Tentáculos sombrios da Ultimate "Drenagem Espinhal" do Chupa-Cabra.
## Conecta o Chupa-Cabra ao kart líder/alvo à frente, renderizando tentáculos
## pulsantes e partículas de energia sendo drenadas do oponente para o predador.

var caster: Kart
var target: Kart
var is_active := true

var _elapsed := 0.0
var _strands: Array[MeshInstance3D] = []
var _light_caster: OmniLight3D
var _light_target: OmniLight3D
var _orb_caster: MeshInstance3D
var _orb_target: MeshInstance3D
var _particles: CPUParticles3D

var _mat_tentacle: StandardMaterial3D
var _mat_core: StandardMaterial3D


func _ready() -> void:
	top_level = true
	_build_visuals()


func setup(p_caster: Kart, p_target: Kart) -> void:
	caster = p_caster
	target = p_target
	if is_instance_valid(caster):
		global_position = caster.ball.global_position


func _build_visuals() -> void:
	# Material dos tentáculos sombrios avermelhados
	_mat_tentacle = StandardMaterial3D.new()
	_mat_tentacle.albedo_color = Color(0.12, 0.02, 0.04) # Sombra escura
	_mat_tentacle.emission_enabled = true
	_mat_tentacle.emission = Color(0.95, 0.08, 0.15) # Brilho vermelho sangue
	_mat_tentacle.emission_energy_multiplier = 2.2
	_mat_tentacle.roughness = 0.45

	_mat_core = StandardMaterial3D.new()
	_mat_core.albedo_color = Color(1.0, 0.15, 0.2)
	_mat_core.emission_enabled = true
	_mat_core.emission = Color(1.0, 0.1, 0.15)
	_mat_core.emission_energy_multiplier = 3.0

	# 3 fios/tentáculos de feixe cilíndrico
	for i in 3:
		var strand := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.045
		cyl.bottom_radius = 0.045
		cyl.height = 1.0
		strand.mesh = cyl
		strand.material_override = _mat_tentacle
		add_child(strand)
		_strands.append(strand)

	# Orbe de ancoragem no Chupa-Cabra
	_orb_caster = MeshInstance3D.new()
	var sm1 := SphereMesh.new()
	sm1.radius = 0.18
	sm1.height = 0.36
	_orb_caster.mesh = sm1
	_orb_caster.material_override = _mat_core
	add_child(_orb_caster)

	# Orbe de drenagem nas costas do alvo
	_orb_target = MeshInstance3D.new()
	var sm2 := SphereMesh.new()
	sm2.radius = 0.22
	sm2.height = 0.44
	_orb_target.mesh = sm2
	_orb_target.material_override = _mat_tentacle
	add_child(_orb_target)

	# Luzes pulsantes
	_light_caster = OmniLight3D.new()
	_light_caster.light_color = Color(1.0, 0.15, 0.15)
	_light_caster.light_energy = 2.4
	_light_caster.omni_range = 4.5
	add_child(_light_caster)

	_light_target = OmniLight3D.new()
	_light_target.light_color = Color(0.85, 0.05, 0.15)
	_light_target.light_energy = 2.8
	_light_target.omni_range = 5.0
	add_child(_light_target)

	# Partículas de sangue/alma fluindo do alvo para o caster
	_particles = CPUParticles3D.new()
	var pmesh := BoxMesh.new()
	pmesh.size = Vector3(0.08, 0.08, 0.08)
	_particles.mesh = pmesh
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_color = Color(1.0, 0.12, 0.2, 0.9)
	_particles.material_override = pmat
	_particles.amount = 24
	_particles.lifetime = 0.8
	_particles.spread = 15.0
	_particles.gravity = Vector3.ZERO
	_particles.initial_velocity_min = 6.0
	_particles.initial_velocity_max = 12.0
	add_child(_particles)


func _process(delta: float) -> void:
	if not is_active:
		return
	if not is_instance_valid(caster) or not is_instance_valid(target):
		break_tether()
		return

	_elapsed += delta

	var p_from: Vector3 = caster.ball.global_position + Vector3.UP * 0.55
	var p_to: Vector3 = target.ball.global_position + Vector3.UP * 0.5
	var diff := p_to - p_from
	var dist := diff.length()

	if dist < 0.2:
		return

	var dir := diff.normalized()

	_orb_caster.global_position = p_from
	_orb_target.global_position = p_to
	_light_caster.global_position = p_from
	_light_target.global_position = p_to

	# Aponta as partículas do alvo para o caster
	_particles.global_position = p_to
	if not dir.is_zero_approx():
		_particles.direction = -dir

	# Atualiza a posição, rotação e escala de cada um dos 3 tentáculos
	var perp1 := dir.cross(Vector3.UP).normalized()
	if perp1.is_zero_approx():
		perp1 = dir.cross(Vector3.RIGHT).normalized()
	var perp2 := dir.cross(perp1).normalized()

	for i in _strands.size():
		var strand := _strands[i]
		var phase: float = _elapsed * 10.0 + float(i) * (TAU / 3.0)
		var wave_amp := 0.35 + sin(phase * 1.5) * 0.15
		var wave_offset := perp1 * (cos(phase) * wave_amp) + perp2 * (sin(phase) * wave_amp)
		var center_pt := (p_from + p_to) * 0.5 + wave_offset

		strand.global_position = center_pt
		# O cilindro tem altura ao longo do eixo Y; alinhamos com a direção
		var strand_len := maxf(dist * 1.02, 0.1)
		(strand.mesh as CylinderMesh).height = strand_len
		
		# Orienta o tentáculo de p_from para p_to
		var up_axis := perp1
		if absf(dir.dot(up_axis)) > 0.95:
			up_axis = perp2
		var basis_z := -dir
		var basis_x := up_axis.cross(basis_z).normalized()
		var basis_y := basis_z.cross(basis_x).normalized()
		strand.global_basis = Basis(basis_x, basis_y, basis_z)
		# Roda 90 graus para que o cilindro (Y) fique no eixo do cabo
		strand.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))


func break_tether() -> void:
	if not is_active:
		return
	is_active = false
	var tween := create_tween()
	tween.tween_property(_mat_tentacle, "emission_energy_multiplier", 0.0, 0.25)
	if _light_caster:
		tween.parallel().tween_property(_light_caster, "light_energy", 0.0, 0.25)
	if _light_target:
		tween.parallel().tween_property(_light_target, "light_energy", 0.0, 0.25)
	tween.tween_callback(queue_free)

