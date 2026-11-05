class_name MenuCamera
extends Camera3D
## Câmera "attract mode" dos menus: passeia devagar pela descida, mostrando o mundo vivo
## atrás das placas de madeira (os menus ficam por cima do cenário do jogo, não de um fundo chapado).

const SPEED := 11.0
const START_DIST := 30.0

var world: Node3D

var _d := START_DIST
var _look := Vector3.ZERO
var _needs_snap := true


func _ready() -> void:
	fov = 62.0
	far = 900.0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func activate() -> void:
	_needs_snap = true
	make_current()


func _process(delta: float) -> void:
	if not current or world == null:
		return
	var samples: Array = world.get("samples")
	if samples.size() < 12:
		return
	var total: float = world.get("total_length")
	_d += SPEED * delta
	if _d > total * 0.85:
		_d = START_DIST
		_needs_snap = true
	var a := _sample(samples, _d)
	var b := _sample(samples, _d + 34.0)
	var target_pos: Vector3 = a["pos"] + a["right"] * 7.5 + Vector3.UP * 6.5 - a["fwd"] * 6.0
	var target_look: Vector3 = b["pos"] + Vector3.UP * 1.5
	if _needs_snap:
		_needs_snap = false
		global_position = target_pos
		_look = target_look
	else:
		global_position = global_position.lerp(target_pos, 1.0 - exp(-2.5 * delta))
		_look = _look.lerp(target_look, 1.0 - exp(-2.0 * delta))
	if global_position.distance_squared_to(_look) > 0.01:
		look_at(_look, Vector3.UP)


func _sample(samples: Array, d: float) -> Dictionary:
	var step: float = maxf(float(samples[1]["dist"]) - float(samples[0]["dist"]), 0.1)
	var f := clampf(d / step, 0.0, float(samples.size() - 2))
	var i := int(f)
	var t := f - float(i)
	var s0: Dictionary = samples[i]
	var s1: Dictionary = samples[i + 1]
	return {
		"pos": (s0["pos"] as Vector3).lerp(s1["pos"], t),
		"right": (s0["right"] as Vector3).lerp(s1["right"], t).normalized(),
		"fwd": (s0["fwd"] as Vector3).lerp(s1["fwd"], t).normalized(),
	}
