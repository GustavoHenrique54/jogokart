extends Node
## Registra o mapa de controles via código (teclado + controle).
## Fica tudo num lugar só e funciona igual no editor, no desktop e na Web.
##
## Teclado:  W/↑ acelera · S/↓ freia/ré · A/D ou ←/→ vira · Espaço/Shift pulo+drift · R reposiciona
## Controle: A ou RT acelera · B ou LT freia · analógico/D-pad vira · RB/LB pulo+drift · Select reposiciona

const DEADZONE := 0.2


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

