extends Node
## Registra o mapa de controles via código (teclado + controle) e detecta qual dispositivo
## o jogador está usando agora (teclado/mouse, controle ou toque), para a interface mostrar
## os ícones certos e ligar/desligar os controles de toque sozinha.
##
## Teclado:  W/↑ empurra · S/↓ freia/ré · A/D ou ←/→ vira · Espaço/Shift pulinho · R reposiciona
## Controle: A ou RT empurra · B ou LT freia · analógico/D-pad vira · RB/LB pulinho · Select reposiciona

enum Device { KEYBOARD, GAMEPAD, TOUCH }

signal device_changed(device: int)

const DEADZONE := 0.2

var device: int = Device.KEYBOARD
var _forced := false


func _ready() -> void:
	_add("accelerate", [KEY_W, KEY_UP], [JOY_BUTTON_A], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_add("brake", [KEY_S, KEY_DOWN], [JOY_BUTTON_B, JOY_BUTTON_X], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_add("steer_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_add("steer_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_add("drift", [KEY_SPACE, KEY_SHIFT], [JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_LEFT_SHOULDER], [])
	_add("ability_damage", [KEY_Q, KEY_J], [JOY_BUTTON_X], [])
	_add("ability_barrier", [KEY_E, KEY_K], [JOY_BUTTON_Y], [])
	_add("respawn", [KEY_R], [JOY_BUTTON_BACK], [])
	_add("toggle_menu", [KEY_ESCAPE], [JOY_BUTTON_START], [])
	if is_touch_platform():
		device = Device.TOUCH
	elif Input.get_connected_joypads().size() > 0:
		device = Device.GAMEPAD


## Celular/tablet nativo ou navegador de celular.
func is_touch_platform() -> bool:
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return true
	if OS.has_feature("web"):
		# iPad moderno se identifica como "Macintosh": checa também os pontos de toque.
		var v: Variant = JavaScriptBridge.eval("/Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent) || (navigator.maxTouchPoints > 1 && /Macintosh/.test(navigator.userAgent))", true)
		return v == true
	return false


func force_device(d: int) -> void:
	_forced = true
	_set_device(d)


func _input(event: InputEvent) -> void:
	if _forced:
		return
	var d := device
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		d = Device.TOUCH
	elif event is InputEventJoypadButton:
		d = Device.GAMEPAD
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > 0.5:
			d = Device.GAMEPAD
	elif event is InputEventKey:
		d = Device.KEYBOARD
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		# Ignora o "mouse de mentira" que o Godot gera a partir do toque.
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			if event is InputEventMouseButton or (event as InputEventMouseMotion).relative.length() > 4.0:
				d = Device.KEYBOARD
	if d != device:
		_set_device(d)


func _set_device(d: int) -> void:
	device = d
	device_changed.emit(d)


func _add(action: StringName, keys: Array, buttons: Array, axes: Array) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action, DEADZONE)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in buttons:
		var ev := InputEventJoypadButton.new()
		ev.button_index = b
		InputMap.action_add_event(action, ev)
	for a in axes:
		var ev := InputEventJoypadMotion.new()
		ev.axis = a[0]
		ev.axis_value = a[1]
		InputMap.action_add_event(action, ev)
