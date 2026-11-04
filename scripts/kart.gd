class_name Kart
extends Node3D
## Controlador do kart — protótipo focado em game feel.
##
## Física: uma esfera (RigidBody3D) invisível faz a colisão e carrega a velocidade.
## Em vez de simular pneus, a cada tick a velocidade é decomposta nos eixos do kart
## (frente / lateral / normal do chão) e reescrita de forma arcade:
##   - frente: curva de aceleração estilo Mario Kart (rápida no início, suaviza no topo)
##   - lateral: "grip" que mata o deslize (bem menor durante o drift)
##   - normal: fica com a física (gravidade, rampas, pulos)
## A direção (heading) é um ângulo próprio do kart, então virar é instantâneo e
## previsível, sem depender de atrito.
##
## Visual: um nó separado (Visual) segue a esfera com interpolação de física,
## alinha com o chão e recebe molas para inclinação (roll/pitch) e squash & stretch.
##
## Rede: quem controla o kart simula; os outros recebem posição/velocidade/estado
## pelo MultiplayerSynchronizer e fazem dead-reckoning + suavização.

const BALL_RADIUS := 0.5
const KART_COLORS := [
	Color(0.92, 0.18, 0.2), Color(0.2, 0.45, 0.95), Color(0.2, 0.8, 0.35), Color(0.98, 0.8, 0.15),
	Color(0.65, 0.3, 0.9), Color(1.0, 0.5, 0.1), Color(0.15, 0.85, 0.85), Color(0.95, 0.4, 0.7),
]
## Cores das faíscas do drift: carregando, azul (mini-turbo), laranja (super), roxo (ultra).
const DRIFT_COLORS := [
	Color(1.0, 0.95, 0.75), Color(0.3, 0.7, 1.0), Color(1.0, 0.55, 0.1), Color(0.85, 0.35, 1.0),
]

@export_group("Velocidade")
@export var max_speed := 26.0 ## m/s (~94 km/h)
@export var acceleration := 24.0 ## m/s² com o kart parado
@export var accel_curve := 2.0 ## maior = mantém aceleração alta por mais tempo e corta perto do topo
@export var brake_decel := 42.0
@export var coast_decel := 7.0
@export var overspeed_decel := 12.0 ## quanto perde por segundo quando está acima da velocidade máxima (pós-turbo)
@export var reverse_speed := 9.0
@export var reverse_accel := 14.0

@export_group("Direção")
@export var turn_speed := 2.5 ## rad/s em velocidade média
@export var turn_speed_high := 1.75 ## rad/s na velocidade máxima
@export var steer_response := 7.0 ## suavização da entrada (teclado vira analógico)
@export var air_turn_factor := 0.45
@export var grip := 12.0 ## quão rápido o deslize lateral morre
@export var drift_grip := 5.5

@export_group("Pulo e Drift")
@export var hop_velocity := 4.6
@export var drift_min_speed := 9.0
@export var drift_turn_min := 1.0 ## rad/s esterçando PARA FORA do drift (curva aberta)
@export var drift_turn_max := 2.7 ## rad/s esterçando PARA DENTRO do drift (curva fechada)
@export var drift_visual_angle := 22.0 ## graus extras de "atravessada" visual
@export var drift_stage_times := PackedFloat32Array([0.85, 1.8, 3.0])
@export var drift_boost_times := PackedFloat32Array([0.55, 1.0, 1.6])

@export_group("Turbo")
@export var boost_speed_mult := 1.38
@export var boost_accel := 70.0
@export var boost_kick := 3.0 ## m/s instantâneos ao soltar um turbo

@export_group("Rede")
@export var remote_correction := 10.0

@onready var ball: RigidBody3D = $Ball
@onready var visual: Node3D = $Visual
@onready var tilt: Node3D = $Visual/Tilt
@onready var squash: Node3D = $Visual/Tilt/Squash
@onready var driver: Node3D = $Visual/Tilt/Squash/Driver
@onready var steer_fl: Node3D = $Visual/Tilt/Squash/SteerFL
@onready var steer_fr: Node3D = $Visual/Tilt/Squash/SteerFR
@onready var wheels: Array[Node3D] = [
	$Visual/Tilt/Squash/SteerFL/WheelFL, $Visual/Tilt/Squash/SteerFR/WheelFR,
	$Visual/Tilt/Squash/WheelRL, $Visual/Tilt/Squash/WheelRR,
]
@onready var name_tag: Label3D = $Visual/NameTag
@onready var sync: MultiplayerSynchronizer = $Sync

# Definidos pelo spawner antes de entrar na árvore.
var peer_id := 1
var player_name := "Piloto"
var slot := 0
var spawn_pos := Vector3(0, 1, 0)
var spawn_heading := 0.0

# Estado replicado (escrito pelo dono, lido pelos outros).
var sync_pos := Vector3.ZERO
var sync_vel := Vector3.ZERO
var sync_heading := 0.0
var sync_state := Vector4.ZERO ## x=steer, y=drift_dir, z=drift_stage, w=turbo
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
var drifting := false
var drift_dir := 0
var drift_charge := 0.0
var drift_stage := 0
var boost_timer := 0.0
var hop_count := 0
var hop_lock := 0.0
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
var _drift_yaw := 0.0
var _roll := 0.0
var _roll_vel := 0.0
var _pitch := 0.0
var _pitch_vel := 0.0
var _squash := 1.0
var _squash_vel := 0.0
var _wheel_spin := 0.0

# FX
var _sparks: Array[CPUParticles3D] = []
var _dust: Array[CPUParticles3D] = []
var _flames: Array[CPUParticles3D] = []
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


func is_boosting() -> bool:
	return boost_timer > 0.0


func get_speed_ratio() -> float:
	return clampf(absf(fwd_speed) / max_speed, 0.0, 1.5)


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
	var accel_in := 0.0
	var brake_in := 0.0
	var steer_in := 0.0
	var drift_held := false
	var drift_pressed := false
	if controls_enabled:
		accel_in = Input.get_action_strength("accelerate")
		brake_in = Input.get_action_strength("brake")
		steer_in = Input.get_axis("steer_right", "steer_left")
		drift_held = Input.is_action_pressed("drift")
		drift_pressed = Input.is_action_just_pressed("drift")
		if Input.is_action_just_pressed("respawn"):
			respawn(spawn_pos, spawn_heading)
			return
	if ball.global_position.y < -25.0:
		respawn(_safe_pos, _safe_heading)
		return

	steer = move_toward(steer, steer_in, steer_response * delta)
	throttle = accel_in - brake_in

	# --- Chão
	hop_lock = maxf(hop_lock - delta, 0.0)
	var was_grounded := grounded
	_probe_ground()
	if hop_lock > 0.0:
		grounded = false
	if grounded:
		if not was_grounded:
			_on_landed(air_time)
		air_time = 0.0
	else:
		air_time += delta

	var up := ground_normal if grounded else Vector3.UP
	var fwd_flat := Vector3(-sin(heading), 0.0, -cos(heading))
	var fwd := (fwd_flat - up * fwd_flat.dot(up)).normalized()
	var right := fwd.cross(up)

	var v := ball.linear_velocity
	var vn := v.dot(up)
	var v_plane := v - up * vn
	fwd_speed = v_plane.dot(fwd)
	var lat := v_plane.dot(right)

	# Batida forte (parede, outro kart): feedback visual.
	var speed_now := v_plane.length()
	if _last_speed - speed_now > 7.0 and was_grounded:
		_on_bump(_last_speed - speed_now)

	boost_timer = maxf(boost_timer - delta, 0.0)

	# --- Longitudinal + grip (só no chão; no ar a física manda)
	if grounded:
		var top := max_speed * (boost_speed_mult if is_boosting() else 1.0)
		if is_boosting():
			fwd_speed = move_toward(fwd_speed, top, boost_accel * delta)
		elif throttle > 0.05:
			if fwd_speed < 0.0:
				fwd_speed = move_toward(fwd_speed, 0.0, brake_decel * delta)
			elif fwd_speed < top:
				var t := fwd_speed / top
				var a := acceleration * maxf(1.0 - pow(t, accel_curve), 0.06)
				fwd_speed = minf(fwd_speed + a * throttle * delta, top)
			else:
				fwd_speed = move_toward(fwd_speed, top, overspeed_decel * delta)
		elif throttle < -0.05:
			if fwd_speed > 0.5:
				fwd_speed = move_toward(fwd_speed, 0.0, brake_decel * -throttle * delta)
			else:
				fwd_speed = move_toward(fwd_speed, -reverse_speed, reverse_accel * delta)
		else:
			var decel := coast_decel if fwd_speed <= top else maxf(coast_decel, overspeed_decel)
			fwd_speed = move_toward(fwd_speed, 0.0, decel * delta)

		lat *= exp(-(drift_grip if drifting else grip) * delta)
		ball.linear_velocity = fwd * fwd_speed + right * lat + up * vn

	long_accel = lerpf(long_accel, (fwd_speed - _last_fwd_speed) / maxf(delta, 0.0001), 1.0 - exp(-12.0 * delta))
	_last_fwd_speed = fwd_speed

	# --- Pulo (hop) e drift estilo Mario Kart
	if drift_pressed and grounded:
		_hop(up)

	if drifting:
		if not drift_held:
			_end_drift(true)
		elif fwd_speed < drift_min_speed * 0.6 or throttle < -0.5:
			_end_drift(false)
		else:
			var inward := steer * drift_dir # -1 = para fora, +1 = para dentro
			if grounded:
				drift_charge += delta * lerpf(0.7, 1.35, (inward + 1.0) * 0.5)
			var new_stage := 0
			for i in drift_stage_times.size():
				if drift_charge >= drift_stage_times[i]:
					new_stage = i + 1
			if new_stage != drift_stage:
				drift_stage = new_stage
				_on_drift_stage_up()
	elif drift_held and grounded and hop_lock <= 0.0 and absf(steer_in) > 0.35 and fwd_speed > drift_min_speed:
		drifting = true
		drift_dir = int(signf(steer_in))
		drift_charge = 0.0
		drift_stage = 0

	# --- Direção
	var speed_ratio := clampf(absf(fwd_speed) / max_speed, 0.0, 1.0)
	var turn := 0.0
	if drifting:
		var inward2 := steer * drift_dir
		turn = drift_dir * lerpf(drift_turn_min, drift_turn_max, (inward2 + 1.0) * 0.5)
	else:
		var power := lerpf(turn_speed, turn_speed_high, speed_ratio) * smoothstep(0.0, 0.15, speed_ratio)
		turn = steer * power * (1.0 if fwd_speed >= -0.1 else -1.0)
	if not grounded:
		turn *= air_turn_factor
	heading = wrapf(heading + turn * delta, -PI, PI)

	# --- Ponto seguro para respawn ao cair
	_safe_timer -= delta
	if grounded and ground_normal.y > 0.95 and _safe_timer <= 0.0:
		_safe_timer = 0.5
		_safe_pos = ball.global_position + Vector3.UP * 0.3
		_safe_heading = heading

	_last_speed = (ball.linear_velocity - up * ball.linear_velocity.dot(up)).length()

	# --- Publica estado para a rede
	sync_pos = ball.global_position
	sync_vel = ball.linear_velocity
	sync_heading = heading
	sync_state = Vector4(steer, drift_dir if drifting else 0, drift_stage, 1.0 if is_boosting() else 0.0)
	sync_hops = hop_count


func _remote_physics(delta: float) -> void:
	if not _has_sync:
		return
	var since := minf((Time.get_ticks_msec() - _last_sync_ms) / 1000.0, 0.25)
	var target := sync_pos + sync_vel * since
	var cur := ball.global_position
	if cur.distance_to(target) > 6.0:
		ball.global_position = target
		ball.reset_physics_interpolation()
	else:
		# Anda com a velocidade recebida e corrige o erro suavemente (sem atraso fixo).
		var predicted := cur + sync_vel * delta
		ball.global_position = predicted.lerp(target, 1.0 - exp(-remote_correction * delta))
	heading = lerp_angle(heading, sync_heading, 1.0 - exp(-20.0 * delta))
	steer = lerpf(steer, sync_state.x, 1.0 - exp(-15.0 * delta))
	drift_dir = int(round(sync_state.y))
	drifting = drift_dir != 0
	drift_stage = int(round(sync_state.z))
	boost_timer = 0.1 if sync_state.w > 0.5 else 0.0
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
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (BALL_RADIUS + 0.35), 1)
	q.exclude = [ball.get_rid()]
	var hit := ball.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit.normal.y > 0.45:
		grounded = true
		ground_normal = hit.normal
	else:
		grounded = false


func _hop(up: Vector3) -> void:
	ball.linear_velocity += up * hop_velocity
	hop_lock = 0.12
	grounded = false
	hop_count += 1
	_hop_fx()


func _end_drift(give_boost: bool) -> void:
	if give_boost and drift_stage > 0:
		apply_boost(drift_boost_times[drift_stage - 1])
	drifting = false
	drift_dir = 0
	drift_charge = 0.0
	drift_stage = 0


## Chamado por drift, boost pads, itens futuros...
func apply_boost(duration: float) -> void:
	boost_timer = maxf(boost_timer, duration)
	var fwd_flat := Vector3(-sin(heading), 0.0, -cos(heading))
	ball.linear_velocity += fwd_flat * boost_kick
	_squash_vel -= 1.5
	_pitch_vel += 1.6
	if camera:
		camera.add_trauma(0.22)
		camera.kick_fov(9.0)


func respawn(pos: Vector3, h: float) -> void:
	_end_drift(false)
	boost_timer = 0.0
	ball.linear_velocity = Vector3.ZERO
	ball.global_position = pos
	heading = h
	prev_heading = h
	vis_heading = h
	fwd_speed = 0.0
	_last_speed = 0.0
	ball.reset_physics_interpolation()
	_squash = 1.4
	_update_visual(0.0)
	if camera:
		camera.snap()


# =========================================================== EVENTOS DE FEEL

func _hop_fx() -> void:
	_squash_vel += 4.5 # estica pra cima


func _on_landed(t_air: float) -> void:
	var impact := clampf(t_air * 1.8, 0.2, 1.0)
	_squash_vel -= 5.0 * impact # amassa
	_pitch_vel -= 1.5 * impact
	if t_air > 0.45:
		_dust_puff = 0.15
		if camera:
			camera.add_trauma(0.35 * impact)


func _on_bump(amount: float) -> void:
	_squash_vel -= clampf(amount * 0.3, 0.5, 4.0)
	_roll_vel += randf_range(-1.0, 1.0) * clampf(amount * 0.4, 1.0, 5.0)
	if camera:
		camera.add_trauma(clampf(amount / 25.0, 0.15, 0.6))


func _on_drift_stage_up() -> void:
	_squash_vel += 1.2
	if camera:
		camera.add_trauma(0.08)


# =========================================================== VISUAL

func _process(delta: float) -> void:
	_update_visual(delta)


func _update_visual(delta: float) -> void:
	var f := Engine.get_physics_interpolation_fraction()
	vis_heading = lerp_angle(prev_heading, heading, f)
	var pos := ball.get_global_transform_interpolated().origin

	var up_target := ground_normal if grounded else Vector3.UP
	_visual_up = _visual_up.slerp(up_target, 1.0 - exp(-12.0 * delta)).normalized() if delta > 0.0 else up_target
	var fwd_flat := Vector3(-sin(vis_heading), 0.0, -cos(vis_heading))
	var fwd := (fwd_flat - _visual_up * fwd_flat.dot(_visual_up)).normalized()
	var right := fwd.cross(_visual_up)
	visual.global_transform = Transform3D(Basis(right, _visual_up, -fwd), pos - _visual_up * BALL_RADIUS)

	if delta <= 0.0:
		return
	var speed_ratio := get_speed_ratio()

	# Atravessada do drift (puramente visual, a física já desliza um pouco).
	var dy_target := 0.0
	if drifting:
		dy_target = drift_dir * deg_to_rad(drift_visual_angle) + steer * deg_to_rad(8.0)
	_drift_yaw = lerp_angle(_drift_yaw, dy_target, 1.0 - exp(-10.0 * delta))

	# Molas: roll (carroceria joga pra fora na curva), pitch (empina/afunda).
	var roll_target := -steer * speed_ratio * deg_to_rad(5.0)
	if drifting:
		roll_target = -drift_dir * deg_to_rad(6.0)
	_roll_vel += (roll_target - _roll) * 140.0 * delta
	_roll_vel *= exp(-11.0 * delta)
	_roll += _roll_vel * delta

	var pitch_target := clampf(long_accel * 0.005, -0.1, 0.1)
	_pitch_vel += (pitch_target - _pitch) * 120.0 * delta
	_pitch_vel *= exp(-10.0 * delta)
	_pitch += _pitch_vel * delta
	tilt.rotation = Vector3(_pitch, _drift_yaw, _roll)

	# Squash & stretch
	_squash_vel += (1.0 - _squash) * 220.0 * delta
	_squash_vel *= exp(-13.0 * delta)
	_squash += _squash_vel * delta
	var s := clampf(_squash, 0.65, 1.45)
	var side := 1.0 / sqrt(s)
	squash.scale = Vector3(side, s, side)

	# Rodas, volante e piloto
	_wheel_spin = wrapf(_wheel_spin - fwd_speed / 0.3 * delta, -TAU, TAU)
	for w in wheels:
		w.rotation.x = _wheel_spin
	var wheel_steer := steer * 0.45
	if drifting:
		wheel_steer = -drift_dir * 0.25 + steer * 0.2 # contra-esterço estiloso
	steer_fl.rotation.y = wheel_steer
	steer_fr.rotation.y = wheel_steer
	driver.rotation = Vector3(0.0, steer * 0.18, steer * 0.22 + (drift_dir * 0.12 if drifting else 0.0))

	_update_fx()


func _apply_color(c: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 0.5
	for path in ["Chassis", "Nose", "Spoiler", "Driver/Head"]:
		var mi := squash.get_node(path) as MeshInstance3D
		mi.set_surface_override_material(0, mat)
	name_tag.modulate = c.lightened(0.4)


func _build_fx() -> void:
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.vertex_color_use_as_albedo = true
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.07, 0.07, 0.22)
	spark_mesh.material = spark_mat

	var dust_mat := StandardMaterial3D.new()
	dust_mat.albedo_color = Color(0.85, 0.82, 0.75)
	dust_mat.roughness = 1.0
	var dust_mesh := SphereMesh.new()
	dust_mesh.radius = 0.18
	dust_mesh.height = 0.36
	dust_mesh.radial_segments = 6
	dust_mesh.rings = 3
	dust_mesh.material = dust_mat

	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0))

	for x in [-0.74, 0.74]:
		var sp := CPUParticles3D.new()
		sp.mesh = spark_mesh
		sp.amount = 28
		sp.lifetime = 0.3
		sp.emitting = false
		sp.local_coords = false
		sp.direction = Vector3(-signf(x) * 0.4, 1.0, 1.0)
		sp.spread = 30.0
		sp.initial_velocity_min = 3.0
		sp.initial_velocity_max = 6.5
		sp.gravity = Vector3(0, -16, 0)
		sp.scale_amount_min = 0.6
		sp.scale_amount_max = 1.3
		sp.scale_amount_curve = shrink
		sp.position = Vector3(x, 0.05, 0.95)
		squash.add_child(sp)
		_sparks.append(sp)

		var du := CPUParticles3D.new()
		du.mesh = dust_mesh
		du.amount = 14
		du.lifetime = 0.6
		du.emitting = false
		du.local_coords = false
		du.direction = Vector3(0, 0.6, 1)
		du.spread = 50.0
		du.initial_velocity_min = 1.0
		du.initial_velocity_max = 2.5
		du.gravity = Vector3(0, 1.5, 0)
		du.scale_amount_min = 0.7
		du.scale_amount_max = 1.4
		du.scale_amount_curve = shrink
		du.position = Vector3(x, 0.1, 0.8)
		squash.add_child(du)
		_dust.append(du)

	var flame_grad := Gradient.new()
	flame_grad.set_color(0, Color(1.0, 0.95, 0.5))
	flame_grad.set_color(1, Color(1.0, 0.25, 0.05))
	for x in [-0.22, 0.22]:
		var fl := CPUParticles3D.new()
		fl.mesh = spark_mesh
		fl.amount = 20
		fl.lifetime = 0.18
		fl.emitting = false
		fl.local_coords = false
		fl.direction = Vector3(0, 0.1, 1)
		fl.spread = 12.0
		fl.initial_velocity_min = 4.0
		fl.initial_velocity_max = 7.0
		fl.gravity = Vector3.ZERO
		fl.scale_amount_min = 1.5
		fl.scale_amount_max = 2.5
		fl.scale_amount_curve = shrink
		fl.color_ramp = flame_grad
		fl.position = Vector3(x, 0.62, 1.28)
		squash.add_child(fl)
		_flames.append(fl)


func _update_fx() -> void:
	var drift_on_ground := drifting and grounded
	var spark_color: Color = DRIFT_COLORS[clampi(drift_stage, 0, DRIFT_COLORS.size() - 1)]
	for sp in _sparks:
		sp.emitting = drift_on_ground and drift_stage > 0
		sp.color = spark_color
	_dust_puff = maxf(_dust_puff - get_process_delta_time(), 0.0)
	for du in _dust:
		du.emitting = drift_on_ground or _dust_puff > 0.0
	var boosting := is_boosting()
	for fl in _flames:
		fl.emitting = boosting
