class_name Kart
extends Node3D
## Controlador do Carrinho de Rolimã — foco em game feel de ladeira / pumptrack.
##
## Física:
## - Uma esfera invisível (RigidBody3D) faz a colisão com o terreno ondulado.
## - Sem drift de turbo artificial: toda a disputa de velocidade vem de LER O RELEVO DA RUA!
## - Quando a frente do carrinho aponta para onde a rua DESCE (fwd.y < 0), ele ganha
##   bastante aceleração e velocidade máxima extra proporcional à inclinação do declive.
## - Quando passa rápido por um ACLIVE súbito (lombada / crista de pumptrack), o carrinho
##   descola do chão e salta naturalmente, sofrendo arrasto aerodinâmico no ar e uma leve
##   perda de velocidade no impacto da aterrissagem.

const BALL_RADIUS := 0.5
const KART_COLORS := [
	Color(0.92, 0.18, 0.2), Color(0.2, 0.45, 0.95), Color(0.2, 0.8, 0.35), Color(0.98, 0.8, 0.15),
	Color(0.65, 0.3, 0.9), Color(1.0, 0.5, 0.1), Color(0.15, 0.85, 0.85), Color(0.95, 0.4, 0.7),
]

@export_group("Velocidade e Relevo (Pumptrack)")
@export var base_flat_speed := 18.0 ## m/s no plano só no embalo/empurrão (~65 km/h)
@export var max_downhill_speed := 40.0 ## m/s máximo rasgando nas partes mais íngremes (~144 km/h)
@export var push_acceleration := 13.0 ## empurrão base quando segura W
@export var downhill_gravity_boost := 58.0 ## ganho forte de velocidade ao pegar onde a rua desce mais
@export var uphill_gravity_drag := 30.0 ## perda de velocidade ao encarar aclive
@export var brake_decel := 38.0
@export var coast_decel := 3.5
@export var overspeed_bleed := 4.5 ## quão devagar o embalo ganho na descida se dissipa no plano
@export var reverse_speed := 7.0
@export var reverse_accel := 11.0

@export_group("Saltos em Aclives")
@export var crest_launch_threshold := 1.4 ## sensibilidade para saltar ao passar por aclive súbito
@export var crest_hop_boost := 1.25 ## impulso vertical ao decolar da crista
@export var air_drag := 0.22 ## perde velocidade enquanto está voando no ar
@export var landing_speed_penalty := 0.12 ## fração de velocidade perdida ao bater de volta no chão (punição de salto)
@export var manual_hop_velocity := 3.8 ## pulinho leve opcional no Espaço

@export_group("Direção")
@export var turn_speed := 2.45 ## rad/s em velocidade baixa/média
@export var turn_speed_high := 1.65 ## rad/s em alta velocidade
@export var steer_response := 7.5
@export var air_turn_factor := 0.35
@export var grip := 13.5 ## rolimã tem boa aderência mas escorrega de leve nas curvas rápidas

@export_group("Rede")
@export var remote_correction := 10.0

@onready var ball: RigidBody3D = $Ball
@onready var visual: Node3D = $Visual
@onready var tilt: Node3D = $Visual/Tilt
@onready var squash: Node3D = $Visual/Tilt/Squash
@onready var driver: Node3D = $Visual/Tilt/Squash/Driver
@onready var front_axle: Node3D = $Visual/Tilt/Squash/FrontAxle
@onready var wheels: Array[Node3D] = [
	$Visual/Tilt/Squash/FrontAxle/WheelFL,
	$Visual/Tilt/Squash/FrontAxle/WheelFR,
	$Visual/Tilt/Squash/WheelRL,
	$Visual/Tilt/Squash/WheelRR,
]
@onready var name_tag: Label3D = $Visual/NameTag
@onready var sync: MultiplayerSynchronizer = $Sync

# Definidos pelo spawner antes de entrar na árvore.
var peer_id := 1
var player_name := "Piloto"
var slot := 0
var spawn_pos := Vector3(0, 1, 0)
var spawn_heading := 0.0

# Estado replicado.
var sync_pos := Vector3.ZERO
var sync_vel := Vector3.ZERO
var sync_heading := 0.0
var sync_state := Vector4.ZERO ## x=steer, y=slope_grade, z=airborne, w=pumping_downhill
var sync_hops := 0

# Estado de simulação.
var controls_enabled := true
var heading := 0.0
var prev_heading := 0.0
var steer := 0.0
var throttle := 0.0
var grounded := false
var ground_normal := Vector3.UP
var air_time := 0.0
var fwd_speed := 0.0
var long_accel := 0.0
var slope_grade := 0.0 ## > 0 descendo (ganhando embalo), < 0 subindo (aclive)
var prev_slope_grade := 0.0
var hop_count := 0
var hop_lock := 0.0
var race_time := 0.0
var finished_time := 0.0
var progress_ratio := 0.0
var camera: KartCamera

var _last_speed := 0.0
var _last_fwd_speed := 0.0
var _safe_pos := Vector3.ZERO
var _safe_heading := 0.0
var _safe_timer := 0.0
var _has_sync := false
var _last_sync_ms := 0

# Estado visual (molas).
var vis_heading := 0.0
var _visual_up := Vector3.UP
var _roll := 0.0
var _roll_vel := 0.0
var _pitch := 0.0
var _pitch_vel := 0.0
var _squash := 1.0
var _squash_vel := 0.0
var _wheel_spin := 0.0

# FX (faíscas de rolamento no asfalto em alta velocidade + poeira)
var _sparks: Array[CPUParticles3D] = []
var _dust: Array[CPUParticles3D] = []
var _dust_puff := 0.0


func _enter_tree() -> void:
	set_multiplayer_authority(peer_id)


func _ready() -> void:
	ball.set_meta("kart", self)
	add_to_group("karts")
	ball.global_position = spawn_pos
	heading = spawn_heading
	prev_heading = heading
	vis_heading = heading
	_safe_pos = spawn_pos
	_safe_heading = spawn_heading
	sync_pos = spawn_pos
	sync_heading = heading
	_apply_color(KART_COLORS[slot % KART_COLORS.size()])
	name_tag.text = player_name
	_build_fx()

	if is_local():
		add_to_group("local_kart")
		name_tag.visible = false
		camera = KartCamera.new()
		camera.kart = self
		add_child(camera)
		camera.make_current()
	else:
		ball.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		ball.freeze = true
		sync.synchronized.connect(_on_synchronized)

	if DisplayServer.get_name() == "headless":
		visual.visible = false
		set_process(false)

	ball.reset_physics_interpolation()
	_update_visual(0.0)
	if camera:
		camera.snap()


func is_local() -> bool:
	return is_multiplayer_authority()


func is_pumping_downhill() -> bool:
	return grounded and slope_grade > 0.09 and fwd_speed > 14.0


func is_boosting() -> bool:
	return is_pumping_downhill()


func get_speed_ratio() -> float:
	return clampf(absf(fwd_speed) / 28.0, 0.0, 1.5)


func get_speed_kmh() -> float:
	return absf(fwd_speed) * 3.6


# =========================================================== FÍSICA

func _physics_process(delta: float) -> void:
	prev_heading = heading
	if is_local():
		_local_physics(delta)
	else:
		_remote_physics(delta)


func _local_physics(delta: float) -> void:
	if finished_time <= 0.0 and controls_enabled:
		race_time += delta

	var accel_in := 0.0
	var brake_in := 0.0
	var steer_in := 0.0
	var hop_pressed := false
	if controls_enabled:
		accel_in = Input.get_action_strength("accelerate")
		brake_in = Input.get_action_strength("brake")
		steer_in = Input.get_axis("steer_right", "steer_left")
		hop_pressed = Input.is_action_just_pressed("drift")
		if Input.is_action_just_pressed("respawn"):
			respawn(_safe_pos, _safe_heading)
			return
	if ball.global_position.y < -2500.0:
		respawn(_safe_pos, _safe_heading)
		return

	steer = move_toward(steer, steer_in, steer_response * delta)
	throttle = accel_in - brake_in

	# --- Detecção do chão e orientação no relevo
	hop_lock = maxf(hop_lock - delta, 0.0)
	var was_grounded := grounded
	_probe_ground()
	if hop_lock > 0.0:
		grounded = false

	var up := ground_normal if grounded else Vector3.UP
	var fwd_flat := Vector3(-sin(heading), 0.0, -cos(heading))
	var fwd := (fwd_flat - up * fwd_flat.dot(up)).normalized()
	var right := fwd.cross(up)

	# slope_grade > 0 significa que a rua na direção do carrinho está DESCENDO
	prev_slope_grade = slope_grade
	slope_grade = -fwd.y if grounded else 0.0

	var v := ball.linear_velocity
	var vn := v.dot(up)
	var v_plane := v - up * vn
	fwd_speed = v_plane.dot(fwd)
	var lat := v_plane.dot(right)

	# Quando passa rápido por um aclive súbito (ou crista depois de subir), o carrinho salta!
	if grounded and was_grounded and fwd_speed > 12.0:
		var grade_change := (prev_slope_grade - slope_grade) / maxf(delta, 0.001)
		if (slope_grade < -0.14 and vn > 1.8) or (grade_change < -crest_launch_threshold and v.y > 1.2):
			ball.linear_velocity.y = maxf(ball.linear_velocity.y * crest_hop_boost, 3.6)
			hop_lock = 0.14
			grounded = false
			hop_count += 1
			_hop_fx()

	if grounded:
		if not was_grounded:
			_on_landed(air_time)
			# Saltar faz perder velocidade no pouso!
			if air_time > 0.18:
				var loss := clampf(air_time * landing_speed_penalty, 0.04, 0.22)
				fwd_speed *= (1.0 - loss)
		air_time = 0.0
	else:
		air_time += delta
		# No ar o carrinho também sofre arrasto aerodinâmico (voar é mais lento que colar nas descidas!)
		var horiz := Vector3(ball.linear_velocity.x, 0.0, ball.linear_velocity.z)
		horiz *= exp(-air_drag * delta)
		ball.linear_velocity.x = horiz.x
		ball.linear_velocity.z = horiz.z
		fwd_speed = horiz.dot(fwd_flat)

	# Batida lateral em mureta/outro carrinho
	var speed_now := v_plane.length()
	if _last_speed - speed_now > 7.0 and was_grounded:
		_on_bump(_last_speed - speed_now)

	# --- Dinâmica longitudinal no chão (pumptrack / descida de ladeira)
	if grounded:
		# Limite de velocidade sobe bastante quando está num bolsão de descida forte
		var downhill_bonus := clampf(slope_grade * 65.0, -5.0, max_downhill_speed - base_flat_speed)
		var current_top := clampf(base_flat_speed + downhill_bonus, 12.0, max_downhill_speed)

		# Aceleração gravitacional da ladeira (empurra mesmo sem segurar W, mas com W rende mais)
		if slope_grade > 0.0:
			var pump_mult := 1.25 if throttle > 0.05 else 0.92
			fwd_speed += slope_grade * downhill_gravity_boost * pump_mult * delta
		elif slope_grade < 0.0:
			fwd_speed += slope_grade * uphill_gravity_drag * delta

		if throttle > 0.05:
			if fwd_speed < 0.0:
				fwd_speed = move_toward(fwd_speed, 0.0, brake_decel * delta)
			elif fwd_speed < current_top:
				var ratio := clampf(fwd_speed / maxf(current_top, 1.0), 0.0, 1.0)
				var a := push_acceleration * maxf(1.0 - pow(ratio, 1.8), 0.12)
				fwd_speed = minf(fwd_speed + a * throttle * delta, current_top)
			else:
				# Mantém o embalo ganho na descida anterior e vai perdendo aos poucos
				fwd_speed = move_toward(fwd_speed, current_top, overspeed_bleed * delta)
		elif throttle < -0.05:
			if fwd_speed > 0.5:
				fwd_speed = move_toward(fwd_speed, 0.0, brake_decel * -throttle * delta)
			else:
				fwd_speed = move_toward(fwd_speed, -reverse_speed, reverse_accel * delta)
		else:
			if fwd_speed > current_top:
				fwd_speed = move_toward(fwd_speed, current_top, overspeed_bleed * delta)
			elif slope_grade <= 0.02:
				fwd_speed = move_toward(fwd_speed, 0.0, coast_decel * delta)

		fwd_speed = clampf(fwd_speed, -reverse_speed, max_downhill_speed)
		lat *= exp(-grip * delta)
		ball.linear_velocity = fwd * fwd_speed + right * lat + up * minf(vn, 2.5)

	long_accel = lerpf(long_accel, (fwd_speed - _last_fwd_speed) / maxf(delta, 0.0001), 1.0 - exp(-12.0 * delta))
	_last_fwd_speed = fwd_speed

	# --- Pulo manual opcional (Espaço)
	if hop_pressed and grounded:
		_hop(up)

	# --- Direção (pelos pés no eixo dianteiro do carrinho de rolimã)
	var speed_ratio := clampf(absf(fwd_speed) / 28.0, 0.0, 1.0)
	var power := lerpf(turn_speed, turn_speed_high, speed_ratio) * smoothstep(0.0, 0.12, speed_ratio)
	var turn := steer * power * (1.0 if fwd_speed >= -0.1 else -1.0)
	if not grounded:
		turn *= air_turn_factor
	heading = wrapf(heading + turn * delta, -PI, PI)

	# --- Checkpoint automático na pista para respawn com R ou queda
	_safe_timer -= delta
	if grounded and ground_normal.y > 0.82 and _safe_timer <= 0.0:
		_safe_timer = 0.6
		_safe_pos = ball.global_position + Vector3.UP * 0.5
		_safe_heading = heading

	_last_speed = (ball.linear_velocity - up * ball.linear_velocity.dot(up)).length()

	# --- Publica estado para a rede
	sync_pos = ball.global_position
	sync_vel = ball.linear_velocity
	sync_heading = heading
	sync_state = Vector4(steer, slope_grade, 0.0 if grounded else 1.0, 1.0 if is_pumping_downhill() else 0.0)
	sync_hops = hop_count


func _remote_physics(delta: float) -> void:
	if not _has_sync:
		return
	var since := minf((Time.get_ticks_msec() - _last_sync_ms) / 1000.0, 0.25)
	var target := sync_pos + sync_vel * since
	var cur := ball.global_position
	if cur.distance_to(target) > 7.0:
		ball.global_position = target
		ball.reset_physics_interpolation()
	else:
		var predicted := cur + sync_vel * delta
		ball.global_position = predicted.lerp(target, 1.0 - exp(-remote_correction * delta))
	heading = lerp_angle(heading, sync_heading, 1.0 - exp(-20.0 * delta))
	steer = lerpf(steer, sync_state.x, 1.0 - exp(-15.0 * delta))
	slope_grade = sync_state.y
	if sync_hops != hop_count:
		hop_count = sync_hops
		_hop_fx()
	var fwd_flat := Vector3(-sin(heading), 0.0, -cos(heading))
	var new_fwd := sync_vel.dot(fwd_flat)
	long_accel = lerpf(long_accel, (new_fwd - fwd_speed) / maxf(delta, 0.0001), 1.0 - exp(-6.0 * delta))
	fwd_speed = new_fwd
	var was_grounded := grounded
	_probe_ground()
	if grounded and not was_grounded:
		_on_landed(air_time)
	air_time = 0.0 if grounded else air_time + delta


func _on_synchronized() -> void:
	_last_sync_ms = Time.get_ticks_msec()
	if not _has_sync:
		_has_sync = true
		ball.global_position = sync_pos
		heading = sync_heading
		prev_heading = heading
		ball.reset_physics_interpolation()


func _probe_ground() -> void:
	var from := ball.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (BALL_RADIUS + 0.42), 1)
	q.exclude = [ball.get_rid()]
	var hit := ball.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit.normal.y > 0.45:
		grounded = true
		ground_normal = hit.normal
	else:
		grounded = false


func _hop(up: Vector3) -> void:
	ball.linear_velocity += up * manual_hop_velocity
	hop_lock = 0.14
	grounded = false
	hop_count += 1
	_hop_fx()


func respawn(pos: Vector3, h: float) -> void:
	ball.linear_velocity = Vector3.ZERO
	ball.global_position = pos
	heading = h
	prev_heading = h
	vis_heading = h
	fwd_speed = 0.0
	_last_speed = 0.0
	ball.reset_physics_interpolation()
	_squash = 1.35
	_update_visual(0.0)
	if camera:
		camera.snap()


func restart_at_top() -> void:
	race_time = 0.0
	finished_time = 0.0
	_safe_pos = spawn_pos
	_safe_heading = spawn_heading
	respawn(spawn_pos, spawn_heading)


# =========================================================== EVENTOS DE FEEL

func _hop_fx() -> void:
	_squash_vel += 4.2


func _on_landed(t_air: float) -> void:
	var impact := clampf(t_air * 1.8, 0.2, 1.0)
	_squash_vel -= 4.8 * impact
	_pitch_vel -= 1.4 * impact
	if t_air > 0.22:
		_dust_puff = 0.22
		if camera:
			camera.add_trauma(0.32 * impact)


func _on_bump(amount: float) -> void:
	_squash_vel -= clampf(amount * 0.3, 0.5, 4.0)
	_roll_vel += randf_range(-1.0, 1.0) * clampf(amount * 0.4, 1.0, 5.0)
	if camera:
		camera.add_trauma(clampf(amount / 25.0, 0.15, 0.55))


# =========================================================== VISUAL

func _process(delta: float) -> void:
	_update_visual(delta)


func _update_visual(delta: float) -> void:
	var f := Engine.get_physics_interpolation_fraction()
	vis_heading = lerp_angle(prev_heading, heading, f)
	var pos := ball.get_global_transform_interpolated().origin

	var up_target := ground_normal if grounded else Vector3.UP
	_visual_up = _visual_up.slerp(up_target, 1.0 - exp(-14.0 * delta)).normalized() if delta > 0.0 else up_target
	var fwd_flat := Vector3(-sin(vis_heading), 0.0, -cos(vis_heading))
	var fwd := (fwd_flat - _visual_up * fwd_flat.dot(_visual_up)).normalized()
	var right := fwd.cross(_visual_up)
	visual.global_transform = Transform3D(Basis(right, _visual_up, -fwd), pos - _visual_up * BALL_RADIUS)

	if delta <= 0.0:
		return
	var speed_ratio := get_speed_ratio()

	# Inclinação do corpo e da tábua nas curvas e mudanças de relevo
	var roll_target := -steer * speed_ratio * deg_to_rad(6.0)
	_roll_vel += (roll_target - _roll) * 140.0 * delta
	_roll_vel *= exp(-11.0 * delta)
	_roll += _roll_vel * delta

	var pitch_target := clampf(long_accel * 0.004, -0.09, 0.09)
	if not grounded:
		pitch_target = clampf(ball.linear_velocity.y * 0.025, -0.22, 0.22)
	_pitch_vel += (pitch_target - _pitch) * 120.0 * delta
	_pitch_vel *= exp(-10.0 * delta)
	_pitch += _pitch_vel * delta
	tilt.rotation = Vector3(_pitch, 0.0, _roll)

	# Squash & stretch
	_squash_vel += (1.0 - _squash) * 220.0 * delta
	_squash_vel *= exp(-13.0 * delta)
	_squash += _squash_vel * delta
	var s := clampf(_squash, 0.65, 1.45)
	var side := 1.0 / sqrt(s)
	squash.scale = Vector3(side, s, side)

	# Rolamentos de aço girando rápido + caibro dianteiro esterçando com os pés
	_wheel_spin = wrapf(_wheel_spin - fwd_speed / 0.15 * delta, -TAU, TAU)
	for w in wheels:
		w.rotation.x = _wheel_spin
	front_axle.rotation.y = steer * 0.42
	# Piloto joga o corpo para dentro da curva e se abaixa nas descidas fortes
	var tuck := -0.18 if is_pumping_downhill() else 0.0
	driver.rotation = Vector3(tuck, steer * 0.16, steer * 0.28)

	_update_fx()


func _apply_color(c: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 0.5
	for path in ["Stripe", "Driver/Torso", "Driver/Head"]:
		var mi := squash.get_node(path) as MeshInstance3D
		mi.set_surface_override_material(0, mat)
	name_tag.modulate = c.lightened(0.4)


func _build_fx() -> void:
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.vertex_color_use_as_albedo = true
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.05, 0.05, 0.2)
	spark_mesh.material = spark_mat

	var dust_mat := StandardMaterial3D.new()
	dust_mat.albedo_color = Color(0.85, 0.82, 0.75)
	dust_mat.roughness = 1.0
	var dust_mesh := SphereMesh.new()
	dust_mesh.radius = 0.15
	dust_mesh.height = 0.3
	dust_mesh.radial_segments = 6
	dust_mesh.rings = 3
	dust_mesh.material = dust_mat

	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0))

	# Faíscas dos rolamentos de aço raspando no asfalto quando pega embalo nas descidas
	for x in [-0.58, 0.58]:
		var sp := CPUParticles3D.new()
		sp.mesh = spark_mesh
		sp.amount = 24
		sp.lifetime = 0.25
		sp.emitting = false
		sp.local_coords = false
		sp.direction = Vector3(-signf(x) * 0.3, 0.8, 1.0)
		sp.spread = 28.0
		sp.initial_velocity_min = 2.5
		sp.initial_velocity_max = 5.5
		sp.gravity = Vector3(0, -16, 0)
		sp.scale_amount_min = 0.5
		sp.scale_amount_max = 1.1
		sp.scale_amount_curve = shrink
		sp.color = Color(1.0, 0.78, 0.3)
		sp.position = Vector3(x, 0.04, 0.75)
		squash.add_child(sp)
		_sparks.append(sp)

		var du := CPUParticles3D.new()
		du.mesh = dust_mesh
		du.amount = 12
		du.lifetime = 0.5
		du.emitting = false
		du.local_coords = false
		du.direction = Vector3(0, 0.6, 1)
		du.spread = 45.0
		du.initial_velocity_min = 1.0
		du.initial_velocity_max = 2.5
		du.gravity = Vector3(0, 1.5, 0)
		du.scale_amount_min = 0.6
		du.scale_amount_max = 1.2
		du.scale_amount_curve = shrink
		du.position = Vector3(x, 0.08, 0.72)
		squash.add_child(du)
		_dust.append(du)


func _update_fx() -> void:
	var fast_downhill := is_pumping_downhill() or (grounded and absf(steer) > 0.65 and fwd_speed > 21.0)
	for sp in _sparks:
		sp.emitting = fast_downhill
	_dust_puff = maxf(_dust_puff - get_process_delta_time(), 0.0)
	for du in _dust:
		du.emitting = _dust_puff > 0.0
