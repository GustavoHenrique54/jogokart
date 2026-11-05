class_name RaceManager
extends Node
## Gerenciador da Corrida e do Semáforo de Largada (3, 2, 1, JÁ!).
## Sincroniza a contagem regressiva via RPC do host/servidor para todos os clientes conectados.
## Mantém os karts travados e imóveis na linha de largada durante o sinal vermelho,
## liberando a física e aceleração exatamente no sinal verde (GO!).

const AudioManagerScript := preload("res://scripts/audio_manager.gd")

enum State {
	IDLE,
	COUNTDOWN,
	RACING,
	FINISHED
}

signal countdown_changed(step: int)
signal race_started
signal race_reset

var state: State = State.IDLE
var current_step: int = -1

var _timer: float = 0.0
var _running_countdown: bool = false
var _step_index: int = 0


func _physics_process(delta: float) -> void:
	# Durante a contagem ou espera, garante que todos os karts fiquem perfeitamente travados no grid
	if state == State.COUNTDOWN or state == State.IDLE:
		for node in get_tree().get_nodes_in_group("karts"):
			if not (node is Kart):
				continue
			var k := node as Kart
			k.controls_enabled = false
			k.fwd_speed = 0.0
			k.ball.linear_velocity = Vector3.ZERO

	# Apenas o servidor (ou modo offline) comanda a passagem do tempo da contagem
	if not _running_countdown:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	_timer -= delta
	if _timer <= 0.0:
		_step_index += 1
		if _step_index == 1:
			_timer = 1.0
			_rpc_sync_countdown.rpc(2)
		elif _step_index == 2:
			_timer = 1.0
			_rpc_sync_countdown.rpc(1)
		elif _step_index == 3:
			_timer = 0.0
			_running_countdown = false
			_rpc_sync_countdown.rpc(0) # 0 = GO! / JÁ!


func start_countdown() -> void:
	# Se for cliente em rede, não inicia sozinho; aguarda o servidor
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	_running_countdown = true
	_step_index = 0
	_timer = 1.0
	_rpc_sync_countdown.rpc(3)


func reset_race() -> void:
	_running_countdown = false
	state = State.IDLE
	current_step = -1
	race_reset.emit()


@rpc("call_local", "reliable")
func _rpc_sync_countdown(step: int) -> void:
	current_step = step
	countdown_changed.emit(step)

	var ui = get_tree().root.find_child("UI", true, false)

	if step in [3, 2, 1]:
		state = State.COUNTDOWN
		# Trava os karts no grid
		for node in get_tree().get_nodes_in_group("karts"):
			if node is Kart:
				var k := node as Kart
				k.controls_enabled = false
				k.fwd_speed = 0.0
				k.ball.linear_velocity = Vector3.ZERO

		# Som do bipe curto 3, 2, 1
		AudioManagerScript.play_countdown_beep(self, false)

		if ui and ui.has_method("show_traffic_light_step"):
			ui.show_traffic_light_step(step)

	elif step == 0:
		# GO! Sinal Verde!
		state = State.RACING
		# Libera a física e aceleração em todos os karts
		for node in get_tree().get_nodes_in_group("karts"):
			if node is Kart:
				var k := node as Kart
				k.controls_enabled = true
				k.race_time = 0.0 # cronômetro oficial inicia agora!

		# Som triunfante agudo do verde
		AudioManagerScript.play_countdown_beep(self, true)

		if ui and ui.has_method("show_traffic_light_step"):
			ui.show_traffic_light_step(0)

		race_started.emit()
