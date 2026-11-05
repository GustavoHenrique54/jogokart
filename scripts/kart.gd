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
const CharacterDataScript := preload("res://scripts/character_data.gd")
const FIRE_ORB_SCENE := preload("res://scenes/fire_orb.tscn")
const PLASMA_BEAM_SCENE := preload("res://scenes/plasma_beam.tscn")

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
var is_preview := false
var peer_id := 1
var player_name := "Piloto"
var character_id: String = CharacterDataScript.BOITATA
var slot := 0
var spawn_pos := Vector3(0, 1, 0)
var spawn_heading := 0.0

# Habilidades e Poderes
var damage_cooldown := 0.0
var damage_max_cooldown := 5.0
var barrier_cooldown := 0.0
var barrier_max_cooldown := 8.0
var barrier_time_left := 0.0
var barrier_active_duration := 4.0

var _fire_shield_node: Node3D
var _psi_shield_node: Node3D
var _shield_mat: StandardMaterial3D

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
	if not is_preview:
		set_multiplayer_authority(peer_id)


func _ready() -> void:
	if is_preview:
		ball.freeze = true
		ball.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		controls_enabled = false
		name_tag.visible = false
		_apply_color(KART_COLORS[slot % KART_COLORS.size()])
		_build_fx()
		_setup_character()
		_build_shields()
		set_physics_process(false)
		ball.global_position = global_position
		_update_visual(0.0)
		return

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
	_setup_character()
	_build_shields()

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
	if not is_inside_tree():
		return true
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
	if damage_cooldown > 0.0:
		damage_cooldown = maxf(damage_cooldown - delta, 0.0)
	if barrier_cooldown > 0.0:
		barrier_cooldown = maxf(barrier_cooldown - delta, 0.0)
	if barrier_time_left > 0.0:
		barrier_time_left = maxf(barrier_time_left - delta, 0.0)
		if barrier_time_left <= 0.0:
			_set_shield_active(false)

	prev_heading = heading
	if is_local():
		_local_physics(delta)
	else:
		_remote_physics(delta)

	if is_barrier_active():
		_process_barrier_repel(delta)


func _local_physics(delta: float) -> void:
	if finished_time <= 0.0 and controls_enabled:
		race_time += delta

	var accel_in := 0.0
	var brake_in := 0.0
	var steer_in := 0.0
	var hop_pressed := false
	if controls_enabled:
		accel_in = GameInput.strength(&"accelerate")
		brake_in = GameInput.strength(&"brake")
		steer_in = GameInput.steer_axis()
		hop_pressed = GameInput.just_pressed(&"drift")
		if GameInput.just_pressed(&"respawn"):
			respawn(_safe_pos, _safe_heading)
			return

		# Ativação das habilidades ativas
		if GameInput.just_pressed(&"ability_damage") and damage_cooldown <= 0.0:
			damage_cooldown = damage_max_cooldown
			var up_vec := ground_normal if grounded else Vector3.UP
			var fwd_f := Vector3(-sin(heading), 0.0, -cos(heading))
			var fwd_dir := (fwd_f - up_vec * fwd_f.dot(up_vec)).normalized()
			var spawn_pt := ball.global_position + fwd_dir * 1.8 + Vector3.UP * 0.35
			_rpc_cast_damage.rpc(spawn_pt, fwd_dir)

		if GameInput.just_pressed(&"ability_barrier") and barrier_cooldown <= 0.0:
			barrier_cooldown = barrier_max_cooldown
			barrier_time_left = barrier_active_duration
			_rpc_activate_barrier.rpc()
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
			# Pouso: ET de Varginha não tem perda de embalo!
			if landing_speed_penalty > 0.0 and air_time > 0.18:
				var loss := clampf(air_time * landing_speed_penalty, 0.04, 0.22)
				fwd_speed *= (1.0 - loss)
		air_time = 0.0
	else:
		air_time += delta
		# No ar o carrinho sofre arrasto aerodinâmico (Cúpula de plasma do ET ou barreira anulam o arrasto!)
		var current_drag := 0.0 if is_barrier_active() else air_drag
		var horiz := Vector3(ball.linear_velocity.x, 0.0, ball.linear_velocity.z)
		horiz *= exp(-current_drag * delta)
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

		# Aceleração da ladeira: a descida só dá embalo enquanto o jogador está empurrando (W).
		# Sem acelerar, o carrinho não ganha velocidade sozinho, nem descendo.
		if slope_grade > 0.0:
			if throttle > 0.05:
				fwd_speed += slope_grade * downhill_gravity_boost * 1.25 * throttle * delta
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
			# Soltou o W: vai perdendo embalo até parar (em qualquer inclinação).
			if fwd_speed > current_top:
				fwd_speed = move_toward(fwd_speed, current_top, overspeed_bleed * delta)
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
	if is_barrier_active():
		return
	_squash_vel -= clampf(amount * 0.3, 0.5, 4.0)
	_roll_vel += randf_range(-1.0, 1.0) * clampf(amount * 0.4, 1.0, 5.0)
	if camera:
		camera.add_trauma(clampf(amount / 25.0, 0.15, 0.55))


# =========================================================== VISUAL

func _process(delta: float) -> void:
	if is_preview:
		ball.global_position = global_position
		heading = rotation.y
		prev_heading = heading
		_update_visual(delta)
		_update_barrier_visual(delta)
		return

	_update_visual(delta)
	_update_barrier_visual(delta)


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
	if ResourceLoader.exists("res://Assets/textures/Ps1Wood_baseColor.png"):
		var wood_mat := StandardMaterial3D.new()
		wood_mat.albedo_texture = load("res://Assets/textures/Ps1Wood_baseColor.png") as Texture2D
		wood_mat.albedo_color = Color(0.92, 0.82, 0.68)
		wood_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		wood_mat.roughness = 0.88
		for wpath in ["Body", "RearAxle", "Backrest", "FrontAxle/Beam"]:
			var wmi := squash.get_node_or_null(wpath) as MeshInstance3D
			if wmi:
				wmi.set_surface_override_material(0, wood_mat)
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


# =========================================================== FOLCLORE & HABILIDADES

func is_barrier_active() -> bool:
	return barrier_time_left > 0.0


func apply_damage_effect(type: String, from_pos: Vector3, force: float) -> void:
	if is_barrier_active():
		# Dano completamente repelido/absorvido pela barreira
		_squash_vel += 2.0
		if camera:
			camera.add_trauma(0.1)
		return

	var dir := (ball.global_position - from_pos).normalized()
	dir.y = maxf(dir.y, 0.28)
	ball.linear_velocity += dir * force
	fwd_speed *= 0.68 # perda temporária de embalo
	_squash_vel -= 5.5
	_roll_vel += randf_range(-3.5, 3.5)
	if camera:
		camera.add_trauma(0.55)


func _process_barrier_repel(_delta: float) -> void:
	for other in get_tree().get_nodes_in_group("karts"):
		if other == self or not (other is Kart):
			continue
		var dist := ball.global_position.distance_to(other.ball.global_position)
		if dist < 2.8:
			var other_ball: Node3D = other.get_node_or_null("Ball")
			if other_ball:
				var repel: Vector3 = (other_ball.global_position - ball.global_position).normalized()
				repel.y = 0.35
				other.ball.linear_velocity += repel * 22.0
				other.fwd_speed *= 0.62
				if other.camera:
					other.camera.add_trauma(0.4)


func _setup_character() -> void:
	if character_id == CharacterDataScript.ET_VARGINHA:
		_setup_et_varginha()
	else:
		_setup_boitata()


func _setup_boitata() -> void:
	# Passiva: Fogo-Fátuo da Floresta (+20% empurrão, sobe aclive com facilidade, tração de fogo)
	push_acceleration = 16.0
	uphill_gravity_drag = 16.0
	grip = 15.5

	# Boitatá fiel ao folclore: A Grande Cobra/Serpente de Fogo Ancestral
	var driver_node := squash.get_node("Driver")
	var leg_l := driver_node.get_node_or_null("LegL")
	var leg_r := driver_node.get_node_or_null("LegR")
	var visor := driver_node.get_node_or_null("Head/Visor")
	if leg_l: leg_l.visible = false
	if leg_r: leg_r.visible = false
	if visor: visor.visible = false

	# Materiais de fogo vivo ancestral
	var mat_fire := StandardMaterial3D.new()
	mat_fire.albedo_color = Color(1.0, 0.24, 0.04)
	mat_fire.roughness = 0.35
	mat_fire.emission_enabled = true
	mat_fire.emission = Color(1.0, 0.35, 0.05)
	mat_fire.emission_energy_multiplier = 1.4

	var mat_ember := StandardMaterial3D.new()
	mat_ember.albedo_color = Color(0.95, 0.65, 0.1)
	mat_ember.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mat_wood_burn := StandardMaterial3D.new()
	mat_wood_burn.albedo_color = Color(0.35, 0.18, 0.1) # Madeira queimada
	mat_wood_burn.roughness = 0.85

	var plank := squash.get_node("Plank") as MeshInstance3D
	if plank: plank.set_surface_override_material(0, mat_wood_burn)

	var stripe := squash.get_node("Stripe") as MeshInstance3D
	if stripe: stripe.set_surface_override_material(0, mat_fire)

	var torso := driver_node.get_node("Torso") as MeshInstance3D
	torso.set_surface_override_material(0, mat_fire)
	torso.scale = Vector3(1.15, 1.0, 1.15)

	var head := driver_node.get_node("Head") as MeshInstance3D
	head.set_surface_override_material(0, mat_fire)
	head.scale = Vector3(1.2, 0.85, 1.35) # Cabeça achatada de serpente mítica

	# Remove customizações antigas de outros heróis
	var old_custom = driver_node.get_node_or_null("CustomMeshRoot")
	if old_custom:
		old_custom.free()

	var custom_root := Node3D.new()
	custom_root.name = "CustomMeshRoot"
	driver_node.add_child(custom_root)

	# 1. Corpo serpentino sinuoso de fogo (anéis da cobra sobre a prancha do rolimã)
	var seg_positions = [
		Vector3(0.0, -0.05, 0.35),
		Vector3(0.18, 0.02, 0.18),
		Vector3(-0.16, 0.08, 0.02),
		Vector3(0.12, 0.16, -0.15),
		Vector3(-0.08, 0.24, -0.32),
		Vector3(0.0, 0.35, -0.45)
	]
	for p in seg_positions:
		var seg := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.28
		seg.mesh = sm
		seg.position = p
		seg.material_override = mat_fire
		custom_root.add_child(seg)

	# 2. Olhos de Sol do Boitatá (enormes globos de fogo amarelo que devoram as sombras)
	for eye_x in [-0.14, 0.14]:
		var eye := MeshInstance3D.new()
		var eye_m := SphereMesh.new()
		eye_m.radius = 0.08
		eye_m.height = 0.15
		eye.mesh = eye_m
		eye.material_override = mat_ember
		eye.position = Vector3(eye_x, 0.72, -0.22)
		custom_root.add_child(eye)

	# Luz radiante dos olhos de fogo do Boitatá
	var fire_glow := OmniLight3D.new()
	fire_glow.light_color = Color(1.0, 0.55, 0.1)
	fire_glow.light_energy = 2.2
	fire_glow.omni_range = 4.0
	fire_glow.position = Vector3(0, 0.72, -0.3)
	custom_root.add_child(fire_glow)

	# 3. Língua bífida bifurcada vermelha flamejante
	var tongue := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.04, 0.015, 0.22)
	tongue.mesh = tm
	var mat_tongue := StandardMaterial3D.new()
	mat_tongue.albedo_color = Color(1.0, 0.1, 0.1)
	mat_tongue.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tongue.material_override = mat_tongue
	tongue.position = Vector3(0, 0.62, -0.38)
	custom_root.add_child(tongue)

	# 4. Crista de labaredas da serpente
	for cr_z in [-0.1, 0.05, 0.2]:
		var cr := MeshInstance3D.new()
		var crm := BoxMesh.new()
		crm.size = Vector3(0.05, 0.18, 0.12)
		cr.mesh = crm
		cr.material_override = mat_ember
		cr.position = Vector3(0, 0.82, cr_z)
		cr.rotation = Vector3(-0.3, 0, 0)
		custom_root.add_child(cr)

	for sp in _sparks:
		sp.color = Color(1.0, 0.45, 0.06)

	name_tag.text = "🔥 Boitatá · " + player_name
	name_tag.modulate = Color(1.0, 0.65, 0.15)


func _setup_et_varginha() -> void:
	# Passiva: Gravidade Ufológica (sem perda de embalo no pouso, arrasto aéreo quase nulo, levitação suave)
	landing_speed_penalty = 0.0
	air_drag = 0.06
	air_turn_factor = 0.70
	if ball:
		ball.gravity_scale = 1.85

	var driver_node := squash.get_node("Driver")
	var leg_l := driver_node.get_node_or_null("LegL") as MeshInstance3D
	var leg_r := driver_node.get_node_or_null("LegR") as MeshInstance3D
	var visor := driver_node.get_node_or_null("Head/Visor")
	if leg_l: leg_l.visible = true
	if leg_r: leg_r.visible = true
	if visor: visor.visible = false

	# ET Padrão dos Filmes: O Clássico "Grey Alien" (Pele cinza suave perolada)
	var mat_grey := StandardMaterial3D.new()
	mat_grey.albedo_color = Color(0.72, 0.75, 0.78) # Cinza clássico alienígena
	mat_grey.roughness = 0.35

	# Grandes Olhos Negros Amendoados dos Filmes (Espelhados e escuros)
	var mat_black_eye := StandardMaterial3D.new()
	mat_black_eye.albedo_color = Color(0.03, 0.03, 0.04) # Preto profundo
	mat_black_eye.metallic = 0.95
	mat_black_eye.roughness = 0.05 # Alto brilho reflexivo

	var mat_saucer_silver := StandardMaterial3D.new()
	mat_saucer_silver.albedo_color = Color(0.82, 0.85, 0.9)
	mat_saucer_silver.metallic = 0.88
	mat_saucer_silver.roughness = 0.2

	var plank := squash.get_node("Plank") as MeshInstance3D
	if plank: plank.set_surface_override_material(0, mat_saucer_silver)

	var stripe := squash.get_node("Stripe") as MeshInstance3D
	if stripe: stripe.set_surface_override_material(0, mat_saucer_silver)

	# Corpo e membros esguios (magros) como nos filmes clássicos de ficção científica
	var torso := driver_node.get_node("Torso") as MeshInstance3D
	torso.set_surface_override_material(0, mat_grey)
	torso.scale = Vector3(0.85, 1.05, 0.85)

	if leg_l:
		leg_l.set_surface_override_material(0, mat_grey)
		leg_l.scale = Vector3(0.8, 1.0, 0.8)
	if leg_r:
		leg_r.set_surface_override_material(0, mat_grey)
		leg_r.scale = Vector3(0.8, 1.0, 0.8)

	var head := driver_node.get_node("Head") as MeshInstance3D
	head.set_surface_override_material(0, mat_grey)
	head.scale = Vector3(1.35, 1.45, 1.15) # Crânio macrocéfalo em forma de gota invertida

	var old_custom = driver_node.get_node_or_null("CustomMeshRoot")
	if old_custom:
		old_custom.free()

	var custom_root := Node3D.new()
	custom_root.name = "CustomMeshRoot"
	driver_node.add_child(custom_root)

	# Topo bulboso da cabeça (formato pêra/gota clássico de ET de Hollywood)
	var bulb := MeshInstance3D.new()
	var bulb_m := SphereMesh.new()
	bulb_m.radius = 0.27
	bulb_m.height = 0.38
	bulb.mesh = bulb_m
	bulb.material_override = mat_grey
	bulb.position = Vector3(0, 0.82, 0.01)
	bulb.scale = Vector3(1.25, 0.9, 1.15)
	custom_root.add_child(bulb)

	# GIGANTESCOS OLHOS NEGROS AMENDOADOS OBLÍQUOS DOS FILMES
	for eye_x in [-0.14, 0.14]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.11
		eye_mesh.height = 0.22
		eye.mesh = eye_mesh
		eye.material_override = mat_black_eye
		eye.position = Vector3(eye_x, 0.72, -0.19)
		eye.scale = Vector3(0.9, 1.35, 0.55)
		eye.rotation = Vector3(0.12, 0, -signf(eye_x) * 0.42) # Inclinação oblíqua marcante dos filmes
		custom_root.add_child(eye)

	# Pequenos orifícios nasais e fenda sutil
	var nose_dot := MeshInstance3D.new()
	var ndm := BoxMesh.new()
	ndm.size = Vector3(0.04, 0.02, 0.02)
	nose_dot.mesh = ndm
	nose_dot.material_override = mat_black_eye
	nose_dot.position = Vector3(0, 0.59, -0.22)
	custom_root.add_child(nose_dot)

	for sp in _sparks:
		sp.color = Color(0.25, 0.95, 0.8)

	name_tag.text = "🛸 ET Clássico · " + player_name
	name_tag.modulate = Color(0.4, 0.9, 1.0)


func _build_shields() -> void:
	# 1. Escudo de Fogo do Boitatá: anel giratório flamejante
	_fire_shield_node = Node3D.new()
	_fire_shield_node.name = "FireShield"
	_fire_shield_node.visible = false
	squash.add_child(_fire_shield_node)

	var torus_mat := StandardMaterial3D.new()
	torus_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	torus_mat.albedo_color = Color(1.0, 0.5, 0.1)

	var torus_mesh := TorusMesh.new()
	torus_mesh.inner_radius = 1.05
	torus_mesh.outer_radius = 1.25
	torus_mesh.rings = 16
	torus_mesh.ring_segments = 8
	torus_mesh.material = torus_mat

	var ring_inst := MeshInstance3D.new()
	ring_inst.mesh = torus_mesh
	ring_inst.position = Vector3(0, 0.25, 0)
	_fire_shield_node.add_child(ring_inst)

	var fire_light := OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.45, 0.08)
	fire_light.light_energy = 2.8
	fire_light.omni_range = 6.0
	_fire_shield_node.add_child(fire_light)

	var fire_part := CPUParticles3D.new()
	var part_mat := StandardMaterial3D.new()
	part_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	part_mat.vertex_color_use_as_albedo = true
	var box_m := BoxMesh.new()
	box_m.size = Vector3(0.12, 0.12, 0.12)
	box_m.material = part_mat
	fire_part.mesh = box_m
	fire_part.amount = 35
	fire_part.lifetime = 0.4
	fire_part.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	fire_part.emission_ring_radius = 1.15
	fire_part.emission_ring_inner_radius = 0.95
	fire_part.emission_ring_height = 0.2
	fire_part.direction = Vector3(0, 1, 0)
	fire_part.spread = 40.0
	fire_part.initial_velocity_min = 1.5
	fire_part.initial_velocity_max = 3.5
	fire_part.gravity = Vector3(0, 4.0, 0)
	fire_part.color = Color(1.0, 0.65, 0.15)
	fire_part.position = Vector3(0, 0.25, 0)
	_fire_shield_node.add_child(fire_part)

	# 2. Cúpula de Força do ET de Varginha: esfera translúcida pulsante
	_psi_shield_node = Node3D.new()
	_psi_shield_node.name = "PsiShield"
	_psi_shield_node.visible = false
	squash.add_child(_psi_shield_node)

	var psi_mat := StandardMaterial3D.new()
	psi_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	psi_mat.albedo_color = Color(0.2, 0.95, 0.7, 0.4)
	psi_mat.roughness = 0.15
	psi_mat.emission_enabled = true
	psi_mat.emission = Color(0.1, 0.8, 0.6)
	psi_mat.emission_energy_multiplier = 0.8

	var sphere_m := SphereMesh.new()
	sphere_m.radius = 1.25
	sphere_m.height = 1.7
	sphere_m.radial_segments = 16
	sphere_m.rings = 8
	sphere_m.material = psi_mat

	var dome_inst := MeshInstance3D.new()
	dome_inst.mesh = sphere_m
	dome_inst.position = Vector3(0, 0.35, 0)
	_psi_shield_node.add_child(dome_inst)

	var psi_light := OmniLight3D.new()
	psi_light.light_color = Color(0.2, 1.0, 0.75)
	psi_light.light_energy = 3.0
	psi_light.omni_range = 6.5
	_psi_shield_node.add_child(psi_light)


func _set_shield_active(active: bool) -> void:
	if character_id == CharacterDataScript.ET_VARGINHA:
		if _psi_shield_node:
			_psi_shield_node.visible = active
		if _fire_shield_node:
			_fire_shield_node.visible = false
	else:
		if _fire_shield_node:
			_fire_shield_node.visible = active
		if _psi_shield_node:
			_psi_shield_node.visible = false


func _update_barrier_visual(delta: float) -> void:
	if not is_barrier_active():
		return
	if _fire_shield_node and _fire_shield_node.visible:
		_fire_shield_node.rotate_y(delta * 7.5)
	if _psi_shield_node and _psi_shield_node.visible:
		var pulse := 1.0 + 0.05 * sin(Time.get_ticks_msec() * 0.012)
		_psi_shield_node.scale = Vector3(pulse, pulse, pulse)


# =========================================================== RPCS DE HABILIDADES

@rpc("call_local", "reliable")
func _rpc_cast_damage(spawn_pt: Vector3, dir: Vector3) -> void:
	var proj: Node3D
	if character_id == CharacterDataScript.ET_VARGINHA:
		proj = PLASMA_BEAM_SCENE.instantiate()
	else:
		proj = FIRE_ORB_SCENE.instantiate()
	get_tree().current_scene.add_child(proj)
	proj.setup(spawn_pt, dir, peer_id)
	if is_local() and camera:
		camera.add_trauma(0.2)


@rpc("call_local", "reliable")
func _rpc_activate_barrier() -> void:
	barrier_time_left = barrier_active_duration
	_set_shield_active(true)
	if is_local() and camera:
		camera.add_trauma(0.12)

