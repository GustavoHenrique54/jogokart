class_name KartCamera
extends Camera3D
## Câmera de perseguição arcade:
## - segue a direção do kart com atraso (mostra a lateral do kart nas curvas/drift)
## - FOV aumenta com a velocidade e dá "kick" no turbo (sensação de velocidade)
## - recua um pouco em alta velocidade
## - screen shake por "trauma" (batidas, aterrissagens, turbos)

@export var distance := 5.0
@export var height := 1.9
@export var look_height := 0.9
@export var look_ahead := 4.0
@export var yaw_follow := 6.5
@export var pos_follow := 16.0
@export var height_follow := 6.0
@export var base_fov := 70.0
@export var speed_fov := 14.0
@export var boost_fov := 7.0

var kart: Kart

var _yaw := 0.0
var _anchor := Vector3.ZERO
var _trauma := 0.0
var _fov_kick := 0.0
var _t := 0.0


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	near = 0.1
	far = 700.0
	fov = base_fov
	snap()


func snap() -> void:
	if kart == null:
		return
	_yaw = kart.vis_heading
	_anchor = kart.visual.global_position
	_place(0.0)


func add_trauma(amount: float) -> void:
	if not Settings.camera_shake:
		return
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func kick_fov(amount: float) -> void:
	_fov_kick = maxf(_fov_kick, amount)


func _process(delta: float) -> void:
	if kart == null:
		return
	var target := kart.visual.global_position
	var kxz := 1.0 - exp(-pos_follow * delta)
	var ky := 1.0 - exp(-height_follow * delta)
	_anchor.x = lerpf(_anchor.x, target.x, kxz)
	_anchor.z = lerpf(_anchor.z, target.z, kxz)
	_anchor.y = lerpf(_anchor.y, target.y, ky)
	_yaw = lerp_angle(_yaw, kart.vis_heading, 1.0 - exp(-yaw_follow * delta))
	_place(delta)


func _place(delta: float) -> void:
	var back := Vector3(sin(_yaw), 0.0, cos(_yaw))
	var ratio := kart.get_speed_ratio()
	var boost := 1.0 if kart.is_boosting() else 0.0
	var dist := distance + ratio * 0.9 + boost * 0.5
	global_position = _anchor + back * dist + Vector3.UP * height
	look_at(_anchor + Vector3.UP * look_height - back * look_ahead, Vector3.UP)

	if delta <= 0.0:
		return
	_fov_kick = move_toward(_fov_kick, 0.0, 14.0 * delta)
	var target_fov := base_fov + minf(ratio, 1.2) * speed_fov + boost * boost_fov + _fov_kick
	fov = lerpf(fov, target_fov, 1.0 - exp(-5.0 * delta))

	_trauma = maxf(_trauma - 1.8 * delta, 0.0)
	_t += delta
	var shake := _trauma * _trauma
	h_offset = shake * 0.3 * (sin(_t * 41.0) + sin(_t * 67.0 + 1.3) * 0.5)
	v_offset = shake * 0.3 * (sin(_t * 53.0 + 2.1) + sin(_t * 79.0) * 0.5)

