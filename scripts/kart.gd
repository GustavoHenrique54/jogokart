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
const FLAME_TRAIL_PATCH_SCRIPT := preload("res://scripts/flame_trail_patch.gd")
const ABDUCTION_BEAM_SCRIPT := preload("res://scripts/abduction_beam.gd")
const TRAP_LOG_SCRIPT := preload("res://scripts/trap_log.gd")
const SPINAL_TETHER_SCRIPT := preload("res://scripts/spinal_tether.gd")
const AudioManagerScript := preload("res://scripts/audio_manager.gd")

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
var damage_max_cooldown := 13.0
var barrier_cooldown := 0.0
var barrier_max_cooldown := 12.0
var barrier_time_left := 0.0
var barrier_active_duration := 4.0
var ultimate_cooldown := 0.0
var ultimate_max_cooldown := 25.0

var flame_trail_time_left := 0.0
var serpent_strike_time_left := 0.0
var antigrav_time_left := 0.0
var abduction_vacuum_time_left := 0.0
var abducted_time_left := 0.0
var curupira_ginga_time_left := 0.0
var curupira_whistle_time_left := 0.0
var curupira_boost_time_left := 0.0
var chupa_bote_time_left := 0.0
var chupa_drain_time_left := 0.0
var chupa_in_slipstream := false
var chupa_land_boost_time_left := 0.0
var _chupa_was_in_bote := false
var _chupa_tether_target: Kart = null
var _chupa_tether_instance: Node3D = null
var _tether_los_blocked_timer := 0.0
var _control_inversion_timer := 0.0
var _misalignment_timer := 0.0
var _flame_drop_timer := 0.0
var _overheat_skid_timer := 0.0
var _line_loss_timer := 0.0
var _hover_offset := 0.0

var _fire_shield_node: Node3D
var _psi_shield_node: Node3D
var _antigrav_thruster_node: Node3D
var _shield_mat: StandardMaterial3D

# Estado replicado.
var sync_pos := Vector3.ZERO
var sync_vel := Vector3.ZERO
var sync_heading := 0.0
var sync_state := Vector4.ZERO ## x=steer, y=slope_grade, z=airborne, w=pumping_downhill
var sync_hops := 0

# Estado de simulação.
var controls_enabled := false
var _audio_roll: AudioStreamPlayer3D
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
	_build_audio()
	controls_enabled = false

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
	if ultimate_cooldown > 0.0:
		ultimate_cooldown = maxf(ultimate_cooldown - delta, 0.0)

	if barrier_time_left > 0.0:
		barrier_time_left = maxf(barrier_time_left - delta, 0.0)
		if barrier_time_left <= 0.0:
			_set_shield_active(false)

	if flame_trail_time_left > 0.0:
		flame_trail_time_left = maxf(flame_trail_time_left - delta, 0.0)

	if serpent_strike_time_left > 0.0:
		serpent_strike_time_left = maxf(serpent_strike_time_left - delta, 0.0)

	if antigrav_time_left > 0.0:
		antigrav_time_left = maxf(antigrav_time_left - delta, 0.0)
		if antigrav_time_left <= 0.0:
			_set_antigrav_thruster_active(false)

	if abduction_vacuum_time_left > 0.0:
		abduction_vacuum_time_left = maxf(abduction_vacuum_time_left - delta, 0.0)

	if abducted_time_left > 0.0:
		var was_abducted := abducted_time_left > 0.0
		abducted_time_left = maxf(abducted_time_left - delta, 0.0)
		if was_abducted and abducted_time_left <= 0.0:
			# Cai seco de volta no asfalto com forte baque
			_on_bump(14.0)
			_squash_vel -= 6.0
			grounded = true
			hop_lock = 0.0

	if _overheat_skid_timer > 0.0:
		_overheat_skid_timer = maxf(_overheat_skid_timer - delta, 0.0)

	if _line_loss_timer > 0.0:
		_line_loss_timer = maxf(_line_loss_timer - delta, 0.0)

	if curupira_ginga_time_left > 0.0:
		curupira_ginga_time_left = maxf(curupira_ginga_time_left - delta, 0.0)

	if curupira_whistle_time_left > 0.0:
		curupira_whistle_time_left = maxf(curupira_whistle_time_left - delta, 0.0)

	if curupira_boost_time_left > 0.0:
		curupira_boost_time_left = maxf(curupira_boost_time_left - delta, 0.0)

	if chupa_bote_time_left > 0.0:
		chupa_bote_time_left = maxf(chupa_bote_time_left - delta, 0.0)
		if chupa_bote_time_left <= 0.0 and _chupa_was_in_bote:
			_chupa_was_in_bote = false
			_on_chupa_bote_land()

	if chupa_land_boost_time_left > 0.0:
		chupa_land_boost_time_left = maxf(chupa_land_boost_time_left - delta, 0.0)

	if chupa_drain_time_left > 0.0:
		chupa_drain_time_left = maxf(chupa_drain_time_left - delta, 0.0)
		if is_local() and _chupa_tether_target != null:
			_process_chupa_tether_drain(delta)

	if _control_inversion_timer > 0.0:
		_control_inversion_timer = maxf(_control_inversion_timer - delta, 0.0)

	if _misalignment_timer > 0.0:
		_misalignment_timer = maxf(_misalignment_timer - delta, 0.0)

	if character_id == CharacterDataScript.CURUPIRA:
		_update_curupira_passive(delta)
	elif character_id == CharacterDataScript.CHUPACABRA:
		_update_chupacabra_passive(delta)

	prev_heading = heading
	_update_rolling_audio(delta)
	if is_local():
		_local_physics(delta)
	else:
		_remote_physics(delta)

	if is_barrier_active():
		_process_barrier_repel(delta)


func _local_physics(delta: float) -> void:
	if not controls_enabled:
		fwd_speed = 0.0
		ball.linear_velocity = Vector3.ZERO
		return

	if finished_time <= 0.0:
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
			AudioManagerScript.play_sound_3d(self, "skill_q", ball.global_position, 0.0, randf_range(0.95, 1.05))
			if character_id == CharacterDataScript.BOITATA:
				flame_trail_time_left = 2.5
				_flame_drop_timer = 0.0
				_rpc_activate_flame_trail.rpc()
			elif character_id == CharacterDataScript.CURUPIRA:
				_rpc_cast_curupira_q.rpc()
			elif character_id == CharacterDataScript.CHUPACABRA:
				_cast_chupacabra_q()
			else:
				var up_vec := ground_normal if grounded else Vector3.UP
				var fwd_f := Vector3(-sin(heading), 0.0, -cos(heading))
				var fwd_dir := (fwd_f - up_vec * fwd_f.dot(up_vec)).normalized()
				var spawn_pt := ball.global_position + fwd_dir * 1.5 + Vector3.UP * 0.72
				_rpc_cast_damage.rpc(spawn_pt, fwd_dir)

		if GameInput.just_pressed(&"ability_barrier") and barrier_cooldown <= 0.0:
			barrier_cooldown = barrier_max_cooldown
			AudioManagerScript.play_sound_3d(self, "skill_e", ball.global_position, 0.0, randf_range(0.95, 1.05))
			if character_id == CharacterDataScript.BOITATA:
				serpent_strike_time_left = 1.5
				_rpc_activate_serpent_strike.rpc()
			elif character_id == CharacterDataScript.CURUPIRA:
				curupira_ginga_time_left = 2.5
				_rpc_activate_curupira_e.rpc()
			elif character_id == CharacterDataScript.CHUPACABRA:
				_cast_chupacabra_e()
			else:
				antigrav_time_left = 3.0
				_rpc_activate_antigrav.rpc()

		if GameInput.just_pressed(&"ability_ultimate") and ultimate_cooldown <= 0.0:
			ultimate_cooldown = ultimate_max_cooldown
			AudioManagerScript.play_sound_3d(self, "skill_r", ball.global_position, 2.0, 1.0)
			_rpc_cast_ultimate.rpc(ball.global_position, heading)

	if ball.global_position.y < -2500.0:
		respawn(_safe_pos, _safe_heading)
		return

	# Levitação dos Rivais pela Abdução Espacial da nave-mãe
	if abducted_time_left > 0.0:
		grounded = false
		hop_lock = 0.15
		fwd_speed = move_toward(fwd_speed, 0.0, 22.0 * delta)
		steer = 0.0
		steer_in = 0.0
		var current_y := ball.global_position.y
		var hover_target_y := _safe_pos.y + 1.1 if absf(current_y - _safe_pos.y) < 8.0 else (current_y + 0.05)
		ball.linear_velocity.y = move_toward(ball.linear_velocity.y, (hover_target_y - current_y) * 4.5, 14.0 * delta)
		ball.linear_velocity.x = move_toward(ball.linear_velocity.x, 0.0, 14.0 * delta)
		ball.linear_velocity.z = move_toward(ball.linear_velocity.z, 0.0, 14.0 * delta)
		_last_fwd_speed = fwd_speed
		heading = wrapf(heading + sin(Time.get_ticks_msec() * 0.007) * 0.3 * delta, -PI, PI)
		return

	# Inversão de Comandos (Confusão Mental do Assobio Ilusório do Curupira)
	if _control_inversion_timer > 0.0:
		steer_in = -steer_in

	# Desalinhamento das Rodas (Impacto da Tora de Arapuca)
	if _misalignment_timer > 0.0:
		steer_in += sin(Time.get_ticks_msec() * 0.038) * 0.48

	# Efeitos ativos sobre o controle direcional
	if serpent_strike_time_left > 0.0:
		# Durante o Bote da Serpente, a sensibilidade da direção cai drasticamente
		steer_in *= 0.14

	var active_steer_response := steer_response
	if is_curupira_e_active():
		active_steer_response *= 1.6

	if _line_loss_timer > 0.0:
		# Perda de Linha: sensibilidade da direção treme e fica mais pesada temporariamente
		steer_in += sin(Time.get_ticks_msec() * 0.03) * 0.38
		steer = move_toward(steer, steer_in, (active_steer_response * 0.42) * delta)
	else:
		steer = move_toward(steer, steer_in, active_steer_response * delta)

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
				var slip_mult := 1.35 if (character_id == CharacterDataScript.CHUPACABRA and chupa_in_slipstream) else 1.0
				fwd_speed += slope_grade * downhill_gravity_boost * 1.25 * throttle * delta * slip_mult
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

		# Habilidade 2 (Mobilidade / Física): Propulsor Antigravitacional do ET
		if is_antigrav_active():
			# Atrito zero: aceleração contínua sem penalidade de superaquecimento dos rolamentos
			fwd_speed = minf(fwd_speed + 15.0 * delta, max_downhill_speed + 8.0)
			_overheat_skid_timer = 0.0

		# Ultimate [R] (Túnel de Vácuo Alienígena): bônus violento de aceleração contínua
		if abduction_vacuum_time_left > 0.0:
			fwd_speed = minf(fwd_speed + 34.0 * delta, max_downhill_speed + 16.0)

		# Habilidade 2 (Mobilidade / Curvas): Ginga da Mata do Curupira
		if is_curupira_e_active():
			_process_ginga_collision(delta)

		# Auto-Buff do Curupira durante o Assobio Ilusório (+30% aceleração contínua na descida)
		if curupira_boost_time_left > 0.0:
			fwd_speed = minf(fwd_speed + 22.0 * delta, max_downhill_speed + 10.0)

		# Passiva: Sede de Embalo do Chupa-Cabra (+35% de ganho de embalo no cone de vácuo ampliado)
		if character_id == CharacterDataScript.CHUPACABRA and chupa_in_slipstream:
			fwd_speed = minf(fwd_speed + 16.0 * delta, max_downhill_speed + 6.0)

		# Habilidade 2 (Mobilidade): Bote Noturno do Chupa-Cabra (Salto rasante sem atrito)
		if is_chupacabra_e_active():
			fwd_speed = minf(fwd_speed + 18.0 * delta, max_downhill_speed + 12.0)

		# Boost de aterrissagem alinhada do Bote Noturno
		if chupa_land_boost_time_left > 0.0:
			fwd_speed = minf(fwd_speed + 10.0 * delta, max_downhill_speed + 6.0)

		# Habilidade 2 (Velocidade): O Bote da Serpente projeta com alta aceleração em linha reta
		if serpent_strike_time_left > 0.0:
			fwd_speed = minf(fwd_speed + 38.0 * delta, max_downhill_speed + 12.0)
			_process_serpent_strike_collision(delta)

		# Habilidade 1 (Dano / Controle): Rastro Flamejante espalha labaredas pelo asfalto
		if flame_trail_time_left > 0.0:
			_flame_drop_timer -= delta
			if _flame_drop_timer <= 0.0:
				_flame_drop_timer = 0.11
				var drop_pos: Vector3 = ball.global_position - fwd * 0.7 + up * 0.05
				_rpc_spawn_flame_trail_patch.rpc(drop_pos, peer_id)

		var extra_top := 0.0
		if serpent_strike_time_left > 0.0:
			extra_top = 12.0
		elif abduction_vacuum_time_left > 0.0:
			extra_top = 16.0
		elif curupira_boost_time_left > 0.0:
			extra_top = 10.0
		elif is_antigrav_active():
			extra_top = 8.0
		elif is_chupacabra_e_active():
			extra_top = 12.0
		elif chupa_drain_time_left > 0.0:
			extra_top = 14.0
		elif chupa_land_boost_time_left > 0.0:
			extra_top = 6.0
		elif character_id == CharacterDataScript.CHUPACABRA and chupa_in_slipstream:
			extra_top = 6.0

		fwd_speed = clampf(fwd_speed, -reverse_speed, max_downhill_speed + extra_top)

		# Deslize inercial sem atrito durante Propulsor Antigravitacional ou Bote Noturno
		var current_grip: float
		if is_antigrav_active() or is_chupacabra_e_active():
			current_grip = 0.85
		elif _overheat_skid_timer > 0.0:
			current_grip = 7.0
		else:
			current_grip = grip
		if chupa_land_boost_time_left > 0.0:
			current_grip *= 1.35
		lat *= exp(-current_grip * delta)
		ball.linear_velocity = fwd * fwd_speed + right * lat + up * minf(vn, 2.5)

	long_accel = lerpf(long_accel, (fwd_speed - _last_fwd_speed) / maxf(delta, 0.0001), 1.0 - exp(-12.0 * delta))
	_last_fwd_speed = fwd_speed

	# --- Pulo manual opcional (Espaço)
	if hop_pressed and grounded:
		_hop(up)

	# --- Direção (pelos pés no eixo dianteiro do carrinho de rolimã)
	var speed_ratio := clampf(absf(fwd_speed) / 28.0, 0.0, 1.0)
	var power := lerpf(turn_speed, turn_speed_high, speed_ratio) * smoothstep(0.0, 0.12, speed_ratio)
	if is_curupira_e_active():
		power *= 1.85 # Ginga da Mata: manobra angular de curva fechada rente à guia interna!
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
	controls_enabled = false
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
	if is_serpent_strike_active() or is_curupira_e_active() or is_chupacabra_e_active():
		return

	if amount > 1.8:
		var impact_vol := clampf(linear_to_db(amount / 16.0), -12.0, 3.0)
		var impact_pitch := randf_range(0.9, 1.1)
		AudioManagerScript.play_sound_3d(self, "kart_impact", ball.global_position, impact_vol, impact_pitch)

	if is_antigrav_active() and amount > 5.0:
		# Se bater de frente em um obstáculo sólido enquanto levita, o impacto é maior e ele é arremessado para o alto!
		ball.linear_velocity.y = maxf(ball.linear_velocity.y, 10.5)
		ball.linear_velocity.x *= 0.28
		ball.linear_velocity.z *= 0.28
		fwd_speed *= 0.28
		hop_lock = 0.6
		grounded = false
		_squash_vel -= 7.5
		_roll_vel += randf_range(-6.0, 6.0)
		_pitch_vel += 8.0
		if camera:
			camera.add_trauma(0.65)
		if is_local():
			var ui = get_tree().root.find_child("UI", true, false)
			if ui and ui.has_method("notify_antigrav_crash"):
				ui.notify_antigrav_crash()
		return
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

	# Efeito visual de levitação (Propulsor Antigravitacional ou Abdução Espacial)
	if is_antigrav_active():
		_hover_offset = move_toward(_hover_offset, 0.22 + sin(Time.get_ticks_msec() * 0.014) * 0.035, 3.0 * delta)
	elif is_abducted():
		_hover_offset = move_toward(_hover_offset, 0.95 + sin(Time.get_ticks_msec() * 0.008) * 0.08, 2.5 * delta)
	else:
		_hover_offset = move_toward(_hover_offset, 0.0, 4.0 * delta)
	squash.position.y = _hover_offset

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


func is_flame_trail_active() -> bool:
	return flame_trail_time_left > 0.0


func is_serpent_strike_active() -> bool:
	return serpent_strike_time_left > 0.0


func is_antigrav_active() -> bool:
	return antigrav_time_left > 0.0


func is_abduction_active() -> bool:
	return abduction_vacuum_time_left > 0.0


func is_abducted() -> bool:
	return abducted_time_left > 0.0


func is_curupira_e_active() -> bool:
	return curupira_ginga_time_left > 0.0


func is_curupira_r_active() -> bool:
	return curupira_whistle_time_left > 0.0


func is_chupacabra_e_active() -> bool:
	return chupa_bote_time_left > 0.0


func is_chupacabra_r_active() -> bool:
	return chupa_drain_time_left > 0.0


func apply_damage_effect(type: String, from_pos: Vector3, force: float) -> void:
	if is_barrier_active() or is_serpent_strike_active() or is_antigrav_active():
		# Dano completamente repelido/absorvido durante barreira ou bote da serpente
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


func apply_flame_trail_hit(_from_pos: Vector3) -> void:
	if is_barrier_active() or is_serpent_strike_active() or is_antigrav_active() or is_chupacabra_e_active():
		return
	fwd_speed *= 0.65 # Perde 35% da velocidade atual
	_overheat_skid_timer = 1.3
	_squash_vel -= 3.6
	_roll_vel += randf_range(-2.8, 2.8)
	if camera:
		camera.add_trauma(0.35)
	if is_local():
		var ui = get_tree().root.find_child("UI", true, false)
		if ui and ui.has_method("notify_wheel_overheat"):
			ui.notify_wheel_overheat()


func apply_blinding_flash() -> void:
	_line_loss_timer = 3.0
	if camera:
		camera.add_trauma(0.45)
	if is_local():
		var ui = get_tree().root.find_child("UI", true, false)
		if ui and ui.has_method("trigger_sun_blind_flash"):
			ui.trigger_sun_blind_flash(1.5)


func apply_telekinetic_hit(_from_pos: Vector3, shoot_dir: Vector3) -> void:
	if is_barrier_active() or is_serpent_strike_active() or is_antigrav_active():
		_squash_vel += 2.0
		if camera:
			camera.add_trauma(0.12)
		return

	# Curto-circuito de impacto que trava bruscamente as rodas de ferro:
	# Perde 40% da velocidade de descida
	fwd_speed *= 0.60

	# Faz o carrinho quicar
	ball.linear_velocity.y = maxf(ball.linear_velocity.y, 4.8)
	_squash_vel -= 7.5

	# Empurra levemente para o lado
	var side_dir := Vector3(-shoot_dir.z, 0.0, shoot_dir.x).normalized()
	var side_sign := 1.0 if randf() > 0.5 else -1.0
	ball.linear_velocity += side_dir * (side_sign * 6.5)
	_roll_vel += side_sign * 4.2
	_overheat_skid_timer = 0.9 # Faíscas elétricas de curto-circuito

	if camera:
		camera.add_trauma(0.48)
	if is_local():
		var ui = get_tree().root.find_child("UI", true, false)
		if ui and ui.has_method("notify_telekinetic_hit"):
			ui.notify_telekinetic_hit()


func apply_abduction_lift(duration: float) -> void:
	if is_barrier_active() or is_serpent_strike_active() or is_antigrav_active():
		return
	abducted_time_left = maxf(abducted_time_left, duration)
	_overheat_skid_timer = 0.0
	if camera:
		camera.add_trauma(0.42)
	if is_local():
		var ui = get_tree().root.find_child("UI", true, false)
		if ui and ui.has_method("notify_abducted"):
			ui.notify_abducted()


func apply_abduction_edge_traction_loss() -> void:
	if is_barrier_active() or is_serpent_strike_active() or is_antigrav_active() or is_abducted():
		return
	_overheat_skid_timer = maxf(_overheat_skid_timer, 0.9)


func apply_trap_log_hit(from_pos: Vector3) -> void:
	if is_barrier_active() or is_serpent_strike_active() or is_chupacabra_e_active():
		return
	# O piloto que colidir com a tora sofre impacto violento:
	# Perde 45% da velocidade atual
	fwd_speed *= 0.55
	# É jogado para o lado da pista e sofre tranco vertical
	var to_kart: Vector3 = (ball.global_position - from_pos).normalized()
	var side_push: Vector3 = to_kart.cross(Vector3.UP).normalized()
	var side_sign := 1.0 if randf() > 0.5 else -1.0
	ball.linear_velocity += side_push * (side_sign * 8.5) + Vector3.UP * 3.8
	_squash_vel -= 8.0
	_roll_vel += side_sign * 5.0
	# Alinhamento das rodas desestabilizado por 1.5s
	_misalignment_timer = 1.5
	if camera:
		camera.add_trauma(0.55)
	if is_local():
		var ui = get_tree().root.find_child("UI", true, false)
		if ui and ui.has_method("notify_trap_log_hit"):
			ui.notify_trap_log_hit()


func apply_illusory_whistle() -> void:
	if is_barrier_active() or is_serpent_strike_active():
		return
	# Inversão de Comandos (esquerda/direita) por 2.5s
	_control_inversion_timer = 2.5
	if camera:
		camera.add_trauma(0.4)
	if is_local():
		var ui = get_tree().root.find_child("UI", true, false)
		if ui and ui.has_method("trigger_illusory_mist"):
			ui.trigger_illusory_mist(2.5)


func _process_ginga_collision(_delta: float) -> void:
	for node in get_tree().get_nodes_in_group("karts"):
		if node == self or not (node is Kart):
			continue
		var other := node as Kart
		var dist := ball.global_position.distance_to(other.ball.global_position)
		if dist < 2.4:
			var to_other: Vector3 = (other.ball.global_position - ball.global_position).normalized()
			to_other.y = 0.2
			# Curupira empurra o adversário para fora da linha sem perder o próprio embalo
			other.ball.linear_velocity += to_other * 22.0
			other.fwd_speed *= 0.75
			if other.camera:
				other.camera.add_trauma(0.4)
			_squash_vel += 2.5


func _process_serpent_strike_collision(_delta: float) -> void:
	for node in get_tree().get_nodes_in_group("karts"):
		if node == self or not (node is Kart):
			continue
		var other := node as Kart
		var dist := ball.global_position.distance_to(other.ball.global_position)
		if dist < 2.5:
			var to_other: Vector3 = (other.ball.global_position - ball.global_position).normalized()
			to_other.y = 0.35
			# Boitatá não perde velocidade: o rival é jogado de lado com força e perde embalo
			other.ball.linear_velocity += to_other * 28.0
			other.fwd_speed *= 0.65
			other.apply_damage_effect("serpent_strike", ball.global_position, 20.0)
			if other.camera:
				other.camera.add_trauma(0.55)
			# Boitatá mantém o embalo do choque!
			_squash_vel += 4.5


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
	elif character_id == CharacterDataScript.CURUPIRA:
		_setup_curupira()
	elif character_id == CharacterDataScript.CHUPACABRA:
		_setup_chupacabra()
	else:
		_setup_boitata()


func _setup_chupacabra() -> void:
	# Metadados e atributos: Predador veloz com alta tração e resposta ágil
	turn_speed = 3.6
	turn_speed_high = 2.8
	grip = 24.0
	damage_max_cooldown = 12.0
	barrier_max_cooldown = 10.0
	ultimate_max_cooldown = 45.0

	var driver_node := squash.get_node("Driver")
	var leg_l := driver_node.get_node_or_null("LegL") as MeshInstance3D
	var leg_r := driver_node.get_node_or_null("LegR") as MeshInstance3D
	var visor := driver_node.get_node_or_null("Head/Visor")
	if leg_l: leg_l.visible = true
	if leg_r: leg_r.visible = true
	if visor: visor.visible = false

	# Materiais do Chupa-Cabra: Pele reptiliana/gárgula escura, espinhos e olhos de sangue
	var mat_skin := StandardMaterial3D.new()
	mat_skin.albedo_color = Color(0.24, 0.22, 0.28) # Tom cinza-arroxeado de couro predador
	mat_skin.roughness = 0.72

	var mat_spine := StandardMaterial3D.new()
	mat_spine.albedo_color = Color(0.72, 0.12, 0.16) # Crista espinhal carmesim
	mat_spine.roughness = 0.5
	mat_spine.emission_enabled = true
	mat_spine.emission = Color(0.65, 0.08, 0.12)
	mat_spine.emission_energy_multiplier = 0.5

	var mat_eye_red := StandardMaterial3D.new()
	mat_eye_red.albedo_color = Color(1.0, 0.05, 0.05)
	mat_eye_red.emission_enabled = true
	mat_eye_red.emission = Color(1.0, 0.02, 0.02)
	mat_eye_red.emission_energy_multiplier = 2.4

	var mat_kart_wood := StandardMaterial3D.new()
	mat_kart_wood.albedo_color = Color(0.18, 0.15, 0.14) # Madeira escura envelhecida
	mat_kart_wood.roughness = 0.9

	var mat_stripe_red := StandardMaterial3D.new()
	mat_stripe_red.albedo_color = Color(0.85, 0.1, 0.15) # Faixa vermelha carmesim
	mat_stripe_red.roughness = 0.5

	var plank := squash.get_node("Plank") as MeshInstance3D
	if plank: plank.set_surface_override_material(0, mat_kart_wood)

	var stripe := squash.get_node("Stripe") as MeshInstance3D
	if stripe: stripe.set_surface_override_material(0, mat_stripe_red)

	var torso := driver_node.get_node("Torso") as MeshInstance3D
	torso.set_surface_override_material(0, mat_skin)
	torso.scale = Vector3(0.95, 0.95, 0.95)

	if leg_l:
		leg_l.set_surface_override_material(0, mat_skin)
		leg_l.rotation = Vector3.ZERO
	if leg_r:
		leg_r.set_surface_override_material(0, mat_skin)
		leg_r.rotation = Vector3.ZERO

	var head := driver_node.get_node("Head") as MeshInstance3D
	head.set_surface_override_material(0, mat_skin)
	head.scale = Vector3(0.95, 0.9, 1.1) # Crânio levemente alongado para frente estilo predador

	var old_custom = driver_node.get_node_or_null("CustomMeshRoot")
	if old_custom:
		old_custom.free()

	var custom_root := Node3D.new()
	custom_root.name = "CustomMeshRoot"
	driver_node.add_child(custom_root)

	# Olhos vermelhos brilhantes do Chupa-Cabra
	for eye_x in [-0.09, 0.09]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.045
		em.height = 0.09
		eye.mesh = em
		eye.material_override = mat_eye_red
		eye.position = Vector3(eye_x, 0.68, -0.22)
		custom_root.add_child(eye)

	var eye_light := OmniLight3D.new()
	eye_light.light_color = Color(1.0, 0.15, 0.15)
	eye_light.light_energy = 1.6
	eye_light.omni_range = 3.2
	eye_light.position = Vector3(0, 0.68, -0.26)
	custom_root.add_child(eye_light)

	# Crista de espinhos dorsais ao longo do pescoço e costas
	var spine_positions := [
		Vector3(0.0, 0.94, -0.05),
		Vector3(0.0, 0.90, 0.10),
		Vector3(0.0, 0.78, 0.22),
		Vector3(0.0, 0.60, 0.28),
		Vector3(0.0, 0.42, 0.32),
		Vector3(0.0, 0.25, 0.35)
	]
	var spine_scales := [
		Vector3(0.05, 0.16, 0.08),
		Vector3(0.06, 0.20, 0.10),
		Vector3(0.07, 0.22, 0.11),
		Vector3(0.06, 0.18, 0.10),
		Vector3(0.05, 0.14, 0.08),
		Vector3(0.04, 0.11, 0.07)
	]
	for idx in spine_positions.size():
		var spine := MeshInstance3D.new()
		var sm := PrismMesh.new()
		spine.mesh = sm
		spine.material_override = mat_spine
		spine.position = spine_positions[idx]
		spine.scale = spine_scales[idx]
		spine.rotation = Vector3(deg_to_rad(-25.0), 0, 0)
		custom_root.add_child(spine)

	# Fagulhas vermelhas nos rolamentos
	for sp in _sparks:
		sp.color = Color(0.9, 0.15, 0.15)

	name_tag.text = "🩸 Chupa-Cabra · " + player_name
	name_tag.modulate = Color(0.95, 0.25, 0.25)


func _setup_curupira() -> void:
	# Passiva: Pegadas Invertidas (maestria em curvas fechadas, alta tração e resposta imediata)
	turn_speed = 3.8
	turn_speed_high = 2.9
	grip = 26.0
	damage_max_cooldown = 13.0
	barrier_max_cooldown = 10.0
	ultimate_max_cooldown = 45.0

	var driver_node := squash.get_node("Driver")
	var leg_l := driver_node.get_node_or_null("LegL") as MeshInstance3D
	var leg_r := driver_node.get_node_or_null("LegR") as MeshInstance3D
	var visor := driver_node.get_node_or_null("Head/Visor")
	if leg_l: leg_l.visible = true
	if leg_r: leg_r.visible = true
	if visor: visor.visible = false

	# Materiais do Curupira: Pele bronzeada e cabelos de fogo flamejantes
	var mat_skin := StandardMaterial3D.new()
	mat_skin.albedo_color = Color(0.72, 0.44, 0.28) # Tom bronze indígena
	mat_skin.roughness = 0.65

	var mat_fire_hair := StandardMaterial3D.new()
	mat_fire_hair.albedo_color = Color(0.98, 0.22, 0.04) # Cabelo vermelho flamejante
	mat_fire_hair.emission_enabled = true
	mat_fire_hair.emission = Color(0.95, 0.35, 0.05)
	mat_fire_hair.emission_energy_multiplier = 1.3

	var mat_forest_wood := StandardMaterial3D.new()
	mat_forest_wood.albedo_color = Color(0.24, 0.16, 0.08) # Tronco rústico escuro da floresta
	mat_forest_wood.roughness = 0.88

	var mat_vine := StandardMaterial3D.new()
	mat_vine.albedo_color = Color(0.18, 0.72, 0.28) # Verde folha / cipó
	mat_vine.roughness = 0.55

	var plank := squash.get_node("Plank") as MeshInstance3D
	if plank: plank.set_surface_override_material(0, mat_forest_wood)

	var stripe := squash.get_node("Stripe") as MeshInstance3D
	if stripe: stripe.set_surface_override_material(0, mat_vine)

	var torso := driver_node.get_node("Torso") as MeshInstance3D
	torso.set_surface_override_material(0, mat_skin)
	torso.scale = Vector3(0.9, 0.95, 0.9)

	# Pés virados para trás (Pegadas Invertidas do Curupira!)
	if leg_l:
		leg_l.set_surface_override_material(0, mat_skin)
		leg_l.rotation = Vector3(0, deg_to_rad(180.0), 0)
	if leg_r:
		leg_r.set_surface_override_material(0, mat_skin)
		leg_r.rotation = Vector3(0, deg_to_rad(180.0), 0)

	var head := driver_node.get_node("Head") as MeshInstance3D
	head.set_surface_override_material(0, mat_skin)
	head.scale = Vector3(1.0, 1.0, 1.0)

	var old_custom = driver_node.get_node_or_null("CustomMeshRoot")
	if old_custom:
		old_custom.free()

	var custom_root := Node3D.new()
	custom_root.name = "CustomMeshRoot"
	driver_node.add_child(custom_root)

	# Cabelos de fogo pontiagudos do Curupira
	var hair_positions := [
		Vector3(0.0, 0.95, 0.02),
		Vector3(-0.08, 0.92, 0.06),
		Vector3(0.08, 0.92, 0.06),
		Vector3(0.0, 0.88, 0.12),
		Vector3(-0.06, 0.86, -0.04),
		Vector3(0.06, 0.86, -0.04)
	]
	var hair_scales := [
		Vector3(0.12, 0.24, 0.12),
		Vector3(0.10, 0.19, 0.10),
		Vector3(0.10, 0.19, 0.10),
		Vector3(0.11, 0.18, 0.11),
		Vector3(0.09, 0.16, 0.09),
		Vector3(0.09, 0.16, 0.09)
	]
	for idx in hair_positions.size():
		var tuft := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tuft.mesh = tm
		tuft.material_override = mat_fire_hair
		tuft.position = hair_positions[idx]
		tuft.scale = hair_scales[idx]
		tuft.rotation = Vector3(deg_to_rad(-15.0), 0, randf_range(-0.15, 0.15))
		custom_root.add_child(tuft)

	# Olhos atentos do guardião
	var mat_eye := StandardMaterial3D.new()
	mat_eye.albedo_color = Color(0.1, 0.1, 0.1)
	for eye_x in [-0.1, 0.1]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.04
		em.height = 0.08
		eye.mesh = em
		eye.material_override = mat_eye
		eye.position = Vector3(eye_x, 0.68, -0.19)
		custom_root.add_child(eye)

	# Faíscas de folhas e mata verde nos rolamentos
	for sp in _sparks:
		sp.color = Color(0.2, 0.85, 0.35)

	name_tag.text = "🍃 Curupira · " + player_name
	name_tag.modulate = Color(0.25, 0.95, 0.45)


func _setup_boitata() -> void:
	# Passiva: Fogo-Fátuo da Floresta (+20% empurrão, sobe aclive com facilidade, tração de fogo)
	push_acceleration = 16.0
	uphill_gravity_drag = 16.0
	grip = 15.5
	damage_max_cooldown = 13.0
	barrier_max_cooldown = 12.0
	ultimate_max_cooldown = 25.0

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
	damage_max_cooldown = 12.0
	barrier_max_cooldown = 14.0
	ultimate_max_cooldown = 26.0
	if ball:
		ball.gravity_scale = 1.85

	var driver_node := squash.get_node("Driver")
	var leg_l := driver_node.get_node_or_null("LegL") as MeshInstance3D
	var leg_r := driver_node.get_node_or_null("LegR") as MeshInstance3D
	var visor := driver_node.get_node_or_null("Head/Visor")
	if leg_l: leg_l.visible = true
	if leg_r: leg_r.visible = true
	if visor: visor.visible = false

	# ET de Varginha e o Clássico "Grey Alien" (Pele cinza suave perolada)
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

	# Os 3 calombos ufológicos na cabeça do ET de Varginha
	var calombos_z := [-0.07, 0.03, 0.13]
	var calombos_y := [0.94, 0.98, 0.93]
	var calombos_r := [0.08, 0.095, 0.08]
	for idx in 3:
		var calombo := MeshInstance3D.new()
		var cm := SphereMesh.new()
		cm.radius = calombos_r[idx]
		cm.height = calombos_r[idx] * 2.0
		calombo.mesh = cm
		calombo.material_override = mat_grey
		calombo.position = Vector3(0, calombos_y[idx], calombos_z[idx])
		calombo.scale = Vector3(1.15, 0.85, 1.15)
		custom_root.add_child(calombo)

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

	name_tag.text = "🛸 ET de Varginha · " + player_name
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

	# 3. Propulsor Antigravitacional do ET de Varginha (dispositivo alienígena soldado no chassi)
	_antigrav_thruster_node = Node3D.new()
	_antigrav_thruster_node.name = "AntigravThruster"
	squash.add_child(_antigrav_thruster_node)

	var thruster_mesh := MeshInstance3D.new()
	var nozzle_cyl := CylinderMesh.new()
	nozzle_cyl.top_radius = 0.11
	nozzle_cyl.bottom_radius = 0.16
	nozzle_cyl.height = 0.2
	thruster_mesh.mesh = nozzle_cyl
	var mat_copper := StandardMaterial3D.new()
	mat_copper.albedo_color = Color(0.78, 0.52, 0.25)
	mat_copper.metallic = 0.85
	thruster_mesh.material_override = mat_copper
	thruster_mesh.position = Vector3(0, -0.04, 0.46)
	thruster_mesh.rotation = Vector3(deg_to_rad(28.0), 0, 0)
	_antigrav_thruster_node.add_child(thruster_mesh)

	var glow_ring := MeshInstance3D.new()
	var t_m := TorusMesh.new()
	t_m.inner_radius = 0.14
	t_m.outer_radius = 0.20
	var mat_cyan := StandardMaterial3D.new()
	mat_cyan.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_cyan.albedo_color = Color(0.25, 0.9, 1.0)
	glow_ring.mesh = t_m
	glow_ring.material_override = mat_cyan
	glow_ring.position = Vector3(0, -0.11, 0.46)
	glow_ring.rotation = Vector3(deg_to_rad(90.0), 0, 0)
	_antigrav_thruster_node.add_child(glow_ring)

	var t_light := OmniLight3D.new()
	t_light.name = "ThrusterLight"
	t_light.light_color = Color(0.2, 0.85, 1.0)
	t_light.light_energy = 0.0
	t_light.omni_range = 5.0
	t_light.position = Vector3(0, -0.15, 0.46)
	_antigrav_thruster_node.add_child(t_light)

	var t_part := CPUParticles3D.new()
	t_part.name = "ThrusterParticles"
	t_part.emitting = false
	t_part.amount = 26
	t_part.lifetime = 0.25
	var p_b := BoxMesh.new()
	p_b.size = Vector3(0.06, 0.06, 0.06)
	var p_m := StandardMaterial3D.new()
	p_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_m.vertex_color_use_as_albedo = true
	p_b.material = p_m
	t_part.mesh = p_b
	t_part.direction = Vector3(0, -1, 0.4)
	t_part.spread = 20.0
	t_part.initial_velocity_min = 3.5
	t_part.initial_velocity_max = 7.0
	t_part.color = Color(0.3, 0.95, 1.0)
	t_part.position = Vector3(0, -0.14, 0.46)
	_antigrav_thruster_node.add_child(t_part)


func _build_audio() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_audio_roll = AudioStreamPlayer3D.new()
	_audio_roll.stream = AudioManagerScript.get_stream("wheel_roll")
	_audio_roll.volume_db = -80.0
	_audio_roll.max_distance = 65.0
	_audio_roll.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_audio_roll.bus = &"Master"
	add_child(_audio_roll)


func _update_rolling_audio(delta: float) -> void:
	if _audio_roll == null or not is_instance_valid(_audio_roll):
		return
	if grounded and controls_enabled and absf(fwd_speed) > 0.4:
		if not _audio_roll.playing:
			_audio_roll.play()
		var speed_ratio := clampf(absf(fwd_speed) / max_downhill_speed, 0.0, 1.25)
		var target_vol := lerpf(-24.0, 2.0, speed_ratio)
		_audio_roll.volume_db = lerpf(_audio_roll.volume_db, target_vol, 1.0 - exp(-10.0 * delta))
		_audio_roll.pitch_scale = lerpf(0.65, 1.45, speed_ratio)
	else:
		_audio_roll.volume_db = move_toward(_audio_roll.volume_db, -80.0, 60.0 * delta)
		if _audio_roll.volume_db <= -70.0 and _audio_roll.playing:
			_audio_roll.stop()


func _set_antigrav_thruster_active(active: bool) -> void:
	if not _antigrav_thruster_node:
		return
	var t_light := _antigrav_thruster_node.get_node_or_null("ThrusterLight") as OmniLight3D
	if t_light:
		t_light.light_energy = 4.2 if active else 0.0
	var t_part := _antigrav_thruster_node.get_node_or_null("ThrusterParticles") as CPUParticles3D
	if t_part:
		t_part.emitting = active


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
	if _antigrav_thruster_node and is_antigrav_active():
		var t_pulse := 1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.02)
		_antigrav_thruster_node.scale = Vector3(t_pulse, t_pulse, t_pulse)
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
func _rpc_activate_antigrav() -> void:
	antigrav_time_left = 3.0
	_overheat_skid_timer = 0.0
	_set_antigrav_thruster_active(true)
	if is_local() and camera:
		camera.add_trauma(0.18)
	if is_local():
		var ui = get_tree().root.find_child("UI", true, false)
		if ui and ui.has_method("notify_antigrav_thruster"):
			ui.notify_antigrav_thruster()


@rpc("call_local", "reliable")
func _rpc_activate_barrier() -> void:
	barrier_time_left = barrier_active_duration
	_set_shield_active(true)
	if is_local() and camera:
		camera.add_trauma(0.12)


@rpc("call_local", "reliable")
func _rpc_activate_flame_trail() -> void:
	flame_trail_time_left = 2.5
	if is_local() and camera:
		camera.add_trauma(0.18)


@rpc("call_local", "reliable")
func _rpc_activate_serpent_strike() -> void:
	serpent_strike_time_left = 1.5
	_squash_vel += 6.5
	if is_local() and camera:
		camera.add_trauma(0.32)


@rpc("call_local", "reliable")
func _rpc_spawn_flame_trail_patch(pos: Vector3, caster_id: int) -> void:
	var patch: Node3D = FLAME_TRAIL_PATCH_SCRIPT.new()
	get_tree().current_scene.add_child(patch)
	patch.setup(pos, caster_id)


@rpc("call_local", "reliable")
func _rpc_cast_ultimate(caster_pos: Vector3, caster_h: float) -> void:
	if character_id == CharacterDataScript.BOITATA:
		_cast_boitata_ultimate(caster_pos, caster_h)
	elif character_id == CharacterDataScript.CURUPIRA:
		_cast_curupira_ultimate(caster_pos, caster_h)
	elif character_id == CharacterDataScript.CHUPACABRA:
		_cast_chupacabra_ultimate(caster_pos, caster_h)
	else:
		_cast_et_ultimate(caster_pos, caster_h)


func _cast_boitata_ultimate(caster_pos: Vector3, _h: float) -> void:
	# Flash de luz solar radiante dos Olhos de Brasas do Boitatá
	var flash_light := OmniLight3D.new()
	flash_light.light_color = Color(1.0, 0.65, 0.15)
	flash_light.light_energy = 8.0
	flash_light.omni_range = 28.0
	flash_light.position = caster_pos + Vector3.UP * 0.8
	get_tree().current_scene.add_child(flash_light)

	var tween := flash_light.create_tween()
	tween.tween_property(flash_light, "light_energy", 0.0, 1.5)
	tween.tween_callback(flash_light.queue_free)

	# Efeito nos outros karts
	for node in get_tree().get_nodes_in_group("karts"):
		if node == self or not (node is Kart):
			continue
		var other := node as Kart
		var dist := caster_pos.distance_to(other.ball.global_position)
		if dist <= 42.0:
			var to_caster: Vector3 = (caster_pos - other.ball.global_position).normalized()
			var rival_fwd := Vector3(-sin(other.heading), 0.0, -cos(other.heading))
			var dot_fwd: float = to_caster.dot(rival_fwd)
			# Quem estiver olhando na direção do Boitatá a até distância média (ou colado a até 14m)
			if dot_fwd > -0.28 or dist <= 14.0:
				other.apply_blinding_flash()

	if is_local() and camera:
		camera.add_trauma(0.3)


func _cast_et_ultimate(caster_pos: Vector3, caster_h: float) -> void:
	# Ultimate [R] — Abdução Espacial (Luz de Nave)
	# Projeta um holofote cilíndrico de luz azulada que varre uma área da pista à frente do ET por 3,5 segundos
	var fwd_dir := Vector3(-sin(caster_h), 0.0, -cos(caster_h)).normalized()
	var spawn_pos := caster_pos + fwd_dir * 18.0

	var beam: Node3D = ABDUCTION_BEAM_SCRIPT.new()
	get_tree().current_scene.add_child(beam)
	beam.setup(spawn_pos, fwd_dir, peer_id)

	# Túnel de Vácuo Alienígena: o ET recebe bônus violento de aceleração contínua
	abduction_vacuum_time_left = 3.5

	if is_local() and camera:
		camera.add_trauma(0.35)
	if is_local():
		var ui = get_tree().root.find_child("UI", true, false)
		if ui and ui.has_method("notify_abduction_cast"):
			ui.notify_abduction_cast()


# =========================================================== HABILIDADES DO CURUPIRA

func _update_curupira_passive(_delta: float) -> void:
	# Passiva: Pegadas Invertidas - maestria nas curvas da mata
	pass


@rpc("call_local", "reliable")
func _rpc_cast_curupira_q() -> void:
	# Habilidade 1 [Q]: Tora de Arapuca
	# Solta uma tora maciça imediatamente atrás do kart
	var up_vec := ground_normal if grounded else Vector3.UP
	var fwd_f := Vector3(-sin(heading), 0.0, -cos(heading))
	var drop_pos: Vector3 = ball.global_position - fwd_f * 2.0 + up_vec * 0.1
	_rpc_spawn_trap_log.rpc(drop_pos, heading, peer_id)
	if is_local() and camera:
		camera.add_trauma(0.18)
	if is_local():
		var ui = get_tree().root.find_child("UI", true, false)
		if ui and ui.has_method("notify_curupira_trap_drop"):
			ui.notify_curupira_trap_drop()


@rpc("call_local", "reliable")
func _rpc_spawn_trap_log(pos: Vector3, spawn_h: float, caster_id: int) -> void:
	var log_node: Node3D = TRAP_LOG_SCRIPT.new()
	get_tree().current_scene.add_child(log_node)
	log_node.setup(pos, spawn_h, caster_id)


@rpc("call_local", "reliable")
func _rpc_activate_curupira_e() -> void:
	# Habilidade 2 [E]: Ginga da Mata (Curva Impossível)
	curupira_ginga_time_left = 2.5
	_squash_vel += 4.5
	if is_local() and camera:
		camera.add_trauma(0.2)
	if is_local():
		var ui = get_tree().root.find_child("UI", true, false)
		if ui and ui.has_method("notify_curupira_ginga"):
			ui.notify_curupira_ginga()


func _cast_curupira_ultimate(caster_pos: Vector3, caster_h: float) -> void:
	# Ultimate [R]: Assobio Ilusório (Pânico na Trilha)
	# Auto-Buff do Curupira: +30% de aceleração contínua por 3 segundos
	curupira_boost_time_left = 3.0
	curupira_whistle_time_left = 2.5

	if is_local() and camera:
		camera.add_trauma(0.25)
	if is_local():
		var ui = get_tree().root.find_child("UI", true, false)
		if ui and ui.has_method("notify_curupira_whistle_cast"):
			ui.notify_curupira_whistle_cast()

	# Aviso de 0.3s antes de aplicar o efeito aos rivais
	await get_tree().create_timer(0.3).timeout

	var fwd_dir := Vector3(-sin(caster_h), 0.0, -cos(caster_h)).normalized()
	for node in get_tree().get_nodes_in_group("karts"):
		if node == self or not (node is Kart):
			continue
		var other := node as Kart
		var to_other: Vector3 = other.ball.global_position - caster_pos
		var dist := to_other.length()
		if dist <= 38.0:
			var dot_fwd: float = fwd_dir.dot(to_other.normalized())
			# Afeta todos os oponentes em um raio médio ao redor e à frente dele
			if dot_fwd > -0.35 or dist <= 12.0:
				other.apply_illusory_whistle()


func _exit_tree() -> void:
	if is_instance_valid(_chupa_tether_instance):
		_chupa_tether_instance.queue_free()
		_chupa_tether_instance = null


# =========================================================== HABILIDADES DO CHUPA-CABRA

func _update_chupacabra_passive(_delta: float) -> void:
	# 1. PASSIVA: Sede de Embalo
	# O cone de vácuo (slipstream) atrás de outros karts é 50% maior em largura e alcance.
	chupa_in_slipstream = false
	if not is_local():
		return
	var my_pos := ball.global_position
	var my_fwd := Vector3(-sin(heading), 0.0, -cos(heading)).normalized()

	for node in get_tree().get_nodes_in_group("karts"):
		if node == self or not (node is Kart):
			continue
		var other := node as Kart
		var to_other := other.ball.global_position - my_pos
		var dist := to_other.length()
		# Cone de alcance ampliado em 50%: até 26 metros de distância
		if dist < 2.0 or dist > 26.0:
			continue

		var to_other_dir := to_other.normalized()
		# O Chupa-Cabra deve estar mirando na direção geral do oponente à frente
		if my_fwd.dot(to_other_dir) < 0.58:
			continue

		# O Chupa-Cabra deve estar posicionado no cone de esteira/vácuo ATRÁS do rival
		var other_fwd := Vector3(-sin(other.heading), 0.0, -cos(other.heading)).normalized()
		var from_other_to_me := (my_pos - other.ball.global_position).normalized()
		# Ângulo do cone 50% mais largo atrás da traseira do rival (dot com other_fwd < -0.42)
		if other_fwd.dot(from_other_to_me) < -0.42:
			chupa_in_slipstream = true
			break


func _cast_chupacabra_q() -> void:
	# 2. HABILIDADE [Q]: Mordida no Eixo
	# Ataque frontal corpo a corpo que atinge o oponente imediatamente à frente (raio de 3 a 4 metros).
	var my_pos := ball.global_position
	var my_fwd := Vector3(-sin(heading), 0.0, -cos(heading)).normalized()
	var hit_target: Kart = null
	var min_dist := 999.0

	for node in get_tree().get_nodes_in_group("karts"):
		if node == self or not (node is Kart):
			continue
		var other := node as Kart
		var to_other := other.ball.global_position - my_pos
		var dist := to_other.length()
		# Cone frontal curto: raio de 3 a 4 metros (3.8m)
		if dist <= 3.8:
			var dot_fwd := my_fwd.dot(to_other.normalized())
			if dot_fwd > 0.52 and dist < min_dist:
				min_dist = dist
				hit_target = other

	if hit_target != null:
		# Acertou! Aplica no alvo penalidade imediata de -40% de velocidade e superaquecimento de 2.5s
		_rpc_axle_bite_hit.rpc(hit_target.peer_id, ball.global_position)
		_squash_vel += 5.0
		if camera:
			camera.add_trauma(0.35)
		var ui = get_tree().root.find_child("UI", true, false)
		if ui and ui.has_method("notify_chupa_bite_success"):
			ui.notify_chupa_bite_success()
	else:
		# Errou o golpe no ar: perde 8% da sua velocidade atual como recuo
		fwd_speed *= 0.92
		_squash_vel -= 3.5
		if camera:
			camera.add_trauma(0.18)
		var ui = get_tree().root.find_child("UI", true, false)
		if ui and ui.has_method("notify_chupa_bite_miss"):
			ui.notify_chupa_bite_miss()


@rpc("call_local", "reliable")
func _rpc_axle_bite_hit(target_peer_id: int, caster_pos: Vector3) -> void:
	for node in get_tree().get_nodes_in_group("karts"):
		if not (node is Kart):
			continue
		var k := node as Kart
		if k.peer_id == target_peer_id:
			k.apply_axle_bite_hit(caster_pos)
			break


func apply_axle_bite_hit(caster_pos: Vector3) -> void:
	if is_barrier_active() or is_serpent_strike_active() or is_chupacabra_e_active():
		return
	# Penalidade imediata de -40% de velocidade
	fwd_speed *= 0.60
	# Superaquecimento temporário das rodas por 2.5s (patina e perde aceleração)
	_overheat_skid_timer = 2.5
	_squash_vel -= 7.0
	_roll_vel += randf_range(-4.0, 4.0)

	# Efeito de tranco físico e faíscas/dentes
	var side_push := (ball.global_position - caster_pos).normalized()
	side_push.y = 0.25
	ball.linear_velocity += side_push * 6.5
	_spawn_bite_fx(ball.global_position)

	if camera:
		camera.add_trauma(0.55)
	if is_local():
		var ui = get_tree().root.find_child("UI", true, false)
		if ui and ui.has_method("notify_axle_bite_received"):
			ui.notify_axle_bite_received()


func _spawn_bite_fx(hit_pos: Vector3) -> void:
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.08, 0.15)
	flash.light_energy = 5.0
	flash.omni_range = 6.0
	flash.position = hit_pos + Vector3.UP * 0.4
	get_tree().current_scene.add_child(flash)

	var parts := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.12, 0.12)
	parts.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.1, 0.15)
	parts.material_override = mat
	parts.amount = 16
	parts.lifetime = 0.5
	parts.one_shot = true
	parts.explosiveness = 0.95
	parts.spread = 180.0
	parts.initial_velocity_min = 4.0
	parts.initial_velocity_max = 8.0
	parts.position = hit_pos + Vector3.UP * 0.4
	get_tree().current_scene.add_child(parts)
	parts.emitting = true

	var tw := flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.45)
	tw.parallel().tween_interval(0.6)
	tw.tween_callback(func():
		if is_instance_valid(flash): flash.queue_free()
		if is_instance_valid(parts): parts.queue_free()
	)


func _cast_chupacabra_e() -> void:
	# 3. HABILIDADE [E]: Bote Noturno
	# Salto rasante para a frente acompanhando o ângulo da ladeira (1.2s de impulso sem atrito).
	_chupa_was_in_bote = true
	chupa_bote_time_left = 1.2
	var up_vec := ground_normal if grounded else Vector3.UP
	var fwd_f := Vector3(-sin(heading), 0.0, -cos(heading)).normalized()

	ball.linear_velocity += fwd_f * 12.0 + up_vec * 3.6
	fwd_speed += 10.0
	_squash_vel += 6.5
	grounded = false
	hop_lock = 0.35
	_rpc_activate_chupa_e.rpc()

	if camera:
		camera.add_trauma(0.22)
	var ui = get_tree().root.find_child("UI", true, false)
	if ui and ui.has_method("notify_chupa_bote"):
		ui.notify_chupa_bote()


@rpc("call_local", "reliable")
func _rpc_activate_chupa_e() -> void:
	chupa_bote_time_left = 1.2
	_squash_vel += 6.0
	_overheat_skid_timer = 0.0


func _on_chupa_bote_land() -> void:
	# Ao aterrissar alinhado à pista, ganha boost temporário de tração/embalo
	var pitch_roll_ok := absf(_pitch) < 0.38 and absf(_roll) < 0.38
	if pitch_roll_ok:
		chupa_land_boost_time_left = 1.5
		_squash_vel -= 3.0
		if is_local():
			var ui = get_tree().root.find_child("UI", true, false)
			if ui and ui.has_method("notify_chupa_land_boost"):
				ui.notify_chupa_land_boost()


func _cast_chupacabra_ultimate(caster_pos: Vector3, caster_h: float) -> void:
	# 4. ULTIMATE [R]: Drenagem Espinhal
	# Localiza o oponente mais próximo à frente em um raio de até 25 metros e cria o vínculo (tether).
	var my_fwd := Vector3(-sin(caster_h), 0.0, -cos(caster_h)).normalized()
	var candidate: Kart = null
	var min_dist := 999.0

	for node in get_tree().get_nodes_in_group("karts"):
		if node == self or not (node is Kart):
			continue
		var other := node as Kart
		var to_other := other.ball.global_position - caster_pos
		var dist := to_other.length()
		if dist <= 25.0:
			var dot_fwd := my_fwd.dot(to_other.normalized())
			if dot_fwd > 0.20 and dist < min_dist:
				min_dist = dist
				candidate = other

	if candidate != null:
		_rpc_tether_start.rpc(peer_id, candidate.peer_id)
	else:
		if is_local():
			var ui = get_tree().root.find_child("UI", true, false)
			if ui and ui.has_method("notify_chupa_tether_broken"):
				ui.notify_chupa_tether_broken("SEM ALVO NO ALCANCE")
			ultimate_cooldown = 4.0 # Não consome todo o cooldown se errar sem nenhum alvo no raio


@rpc("call_local", "reliable")
func _rpc_tether_start(caster_peer_id: int, target_peer_id: int) -> void:
	var caster_kart: Kart = null
	var target_kart: Kart = null
	for node in get_tree().get_nodes_in_group("karts"):
		if not (node is Kart):
			continue
		var k := node as Kart
		if k.peer_id == caster_peer_id:
			caster_kart = k
		elif k.peer_id == target_peer_id:
			target_kart = k

	if caster_kart and target_kart:
		if is_instance_valid(caster_kart._chupa_tether_instance):
			caster_kart._chupa_tether_instance.queue_free()

		var tether: Node3D = SPINAL_TETHER_SCRIPT.new()
		get_tree().current_scene.add_child(tether)
		tether.setup(caster_kart, target_kart)
		caster_kart._chupa_tether_instance = tether
		caster_kart._chupa_tether_target = target_kart
		caster_kart.chupa_drain_time_left = 4.0
		caster_kart._tether_los_blocked_timer = 0.0

		if caster_kart.is_local():
			var ui = get_tree().root.find_child("UI", true, false)
			if ui and ui.has_method("notify_chupa_tether_started"):
				ui.notify_chupa_tether_started()
			if caster_kart.camera:
				caster_kart.camera.add_trauma(0.35)


@rpc("call_local", "reliable")
func _rpc_tether_end(caster_peer_id: int, _target_peer_id: int, reason: String) -> void:
	for node in get_tree().get_nodes_in_group("karts"):
		if not (node is Kart):
			continue
		var k := node as Kart
		if k.peer_id == caster_peer_id:
			if is_instance_valid(k._chupa_tether_instance):
				if k._chupa_tether_instance.has_method("break_tether"):
					k._chupa_tether_instance.break_tether()
				else:
					k._chupa_tether_instance.queue_free()
				k._chupa_tether_instance = null
			k.chupa_drain_time_left = 0.0
			k._chupa_tether_target = null
			if k.is_local():
				var ui = get_tree().root.find_child("UI", true, false)
				if ui and ui.has_method("notify_chupa_tether_broken"):
					ui.notify_chupa_tether_broken(reason)
			break


func _process_chupa_tether_drain(delta: float) -> void:
	if _chupa_tether_target == null or not is_instance_valid(_chupa_tether_target):
		_rpc_tether_end.rpc(peer_id, -1, "alvo desconectado")
		return

	var my_pos := ball.global_position
	var target_pos := _chupa_tether_target.ball.global_position
	var dist := my_pos.distance_to(target_pos)

	# Condição de quebra 1: Se o alvo abrir mais de 35 metros de distância
	if dist > 35.0:
		_rpc_tether_end.rpc(peer_id, _chupa_tether_target.peer_id, "distância máxima")
		return

	# Condição de quebra 2: Tempo expirou
	if chupa_drain_time_left <= 0.0:
		_rpc_tether_end.rpc(peer_id, _chupa_tether_target.peer_id, "concluído")
		return

	# Condição de quebra 3: Linha de visada cortada por obstáculo grande / curva fechada
	var space := get_world_3d().direct_space_state
	if space:
		var query := PhysicsRayQueryParameters3D.create(my_pos + Vector3.UP * 0.5, target_pos + Vector3.UP * 0.5)
		query.exclude = [ball, _chupa_tether_target.ball]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			var col = hit.get("collider")
			if col and not (col is RigidBody3D and col.get_parent() is Kart):
				_tether_los_blocked_timer += delta
				if _tether_los_blocked_timer > 0.4:
					_rpc_tether_end.rpc(peer_id, _chupa_tether_target.peer_id, "visão bloqueada")
					return
		else:
			_tether_los_blocked_timer = maxf(_tether_los_blocked_timer - delta * 2.0, 0.0)

	# Drenagem contínua:
	# O alvo perde velocidade de descida a uma taxa aproximada de 8% por segundo
	var drain_fraction := 0.08 * delta
	var target_loss := _chupa_tether_target.fwd_speed * drain_fraction
	_chupa_tether_target.fwd_speed = maxf(_chupa_tether_target.fwd_speed - target_loss, 0.0)

	# O Chupa-Cabra absorve esse valor para seu próprio vetor de aceleração
	fwd_speed = minf(fwd_speed + (target_loss * 1.6 + 12.0 * delta), max_downhill_speed + 14.0)
