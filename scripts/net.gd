extends Node
## Camada de rede (autoload "Net").
##
## Arquitetura do protótipo:
## - Topologia estrela via WebSocket (funciona em navegador E desktop).
## - O SERVIDOR é sempre uma build nativa (editor/desktop ou headless), porque
##   um navegador não consegue abrir uma porta para escutar conexões.
## - Cada kart é simulado por quem o controla (client-authoritative). Isso dá
##   resposta instantânea aos controles (zero input lag), que é o mais importante
##   para o game feel. O servidor apenas faz spawn/despawn e repassa (relay) o
##   estado dos karts entre os jogadores. Mais tarde dá para migrar para
##   predição + reconciliação com servidor autoritativo, se necessário.

signal status_changed(text: String)
signal session_started
signal session_ended(reason: String)
signal player_registered(id: int, player_name: String, character_id: String) ## só no servidor
signal player_left(id: int) ## só no servidor

const DEFAULT_PORT := 8080

var player_name := "Piloto"
var player_character := "boitata"
var in_session := false
var is_dedicated := false
var ping_ms := -1

var _ping_timer := 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	# Ping simples (RTT) para debug de rede.
	if in_session and multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_ping_timer -= delta
		if _ping_timer <= 0.0:
			_ping_timer = 1.0
			_ping.rpc_id(1, Time.get_ticks_msec())


# ---------------------------------------------------------------- API pública

func is_web() -> bool:
	return OS.has_feature("web")


## Argumentos de linha de comando: godot --headless -- --server --port=8080
func wants_dedicated_server() -> bool:
	return "--server" in OS.get_cmdline_user_args() or "--server" in OS.get_cmdline_args()


func cmdline_port() -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			return arg.trim_prefix("--port=").to_int()
	return DEFAULT_PORT


## Na Web, permite compartilhar um link tipo https://seujogo.vercel.app/?server=wss://xxxx.trycloudflare.com
func server_from_page_url() -> String:
	if not is_web():
		return ""
	var v = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('server') || ''", true)
	return str(v) if v != null else ""


func host(port: int = DEFAULT_PORT, dedicated := false) -> Error:
	leave(false)
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		status_changed.emit("Falha ao abrir servidor na porta %d (erro %d). A porta já está em uso?" % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	is_dedicated = dedicated
	in_session = true
	status_changed.emit("Servidor aberto na porta %d" % port)
	print("[Net] Servidor WebSocket escutando na porta %d (dedicado=%s)" % [port, dedicated])
	session_started.emit()
	if not dedicated:
		player_registered.emit(1, player_name, player_character)
	return OK


func join(address: String) -> Error:
	leave(false)
	var url := normalize_url(address)
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err != OK:
		status_changed.emit("Endereço inválido: %s (erro %d)" % [url, err])
		return err
	multiplayer.multiplayer_peer = peer
	status_changed.emit("Conectando em %s ..." % url)
	print("[Net] Conectando em ", url)
	return OK


func start_offline() -> void:
	leave(false)
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	in_session = true
	status_changed.emit("Modo treino (offline)")
	session_started.emit()
	player_registered.emit(1, player_name, player_character)


func leave(emit_signal_ended := true) -> void:
	var was := in_session
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	in_session = false
	ping_ms = -1
	if was and emit_signal_ended:
		session_ended.emit("Você saiu da sessão.")


## Aceita: "localhost", "192.168.0.10:8080", "https://abc.trycloudflare.com",
## "wss://abc.trycloudflare.com", "abc.trycloudflare.com" ...
func normalize_url(address: String) -> String:
	var a := address.strip_edges()
	if a.is_empty():
		return "ws://localhost:%d" % DEFAULT_PORT
	if a.begins_with("https://"):
		a = "wss://" + a.trim_prefix("https://")
	elif a.begins_with("http://"):
		a = "ws://" + a.trim_prefix("http://")
	if not a.contains("://"):
		var host_part := a.get_slice("/", 0)
		var is_local := host_part.begins_with("localhost") or host_part.begins_with("127.") \
				or host_part.begins_with("192.168.") or host_part.begins_with("10.") \
				or host_part.get_slice(":", 0).is_valid_ip_address()
		if is_local:
			if not host_part.contains(":"):
				a = a.replace(host_part, "%s:%d" % [host_part, DEFAULT_PORT])
			a = "ws://" + a
		else:
			a = "wss://" + a
	return a.trim_suffix("/")


# ---------------------------------------------------------------- callbacks

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		print("[Net] Peer conectou: ", id)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		print("[Net] Peer saiu: ", id)
		player_left.emit(id)


func _on_connected_to_server() -> void:
	in_session = true
	status_changed.emit("Conectado! id=%d" % multiplayer.get_unique_id())
	session_started.emit()
	_register.rpc_id(1, player_name, player_character)


func _on_connection_failed() -> void:
	in_session = false
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	status_changed.emit("Não foi possível conectar. Confira o endereço e se o host está online.")
	session_ended.emit("Falha na conexão.")


func _on_server_disconnected() -> void:
	in_session = false
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	status_changed.emit("O servidor fechou a conexão.")
	session_ended.emit("Servidor desconectado.")


# ---------------------------------------------------------------- RPCs

@rpc("any_peer", "call_remote", "reliable")
func _register(pname: String, pchar: String = "boitata") -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	pname = pname.strip_edges().left(16)
	if pname.is_empty():
		pname = "Piloto %d" % (id % 1000)
	if pchar.is_empty():
		pchar = "boitata"
	print("[Net] Jogador registrado: %s (%d) [Personagem: %s]" % [pname, id, pchar])
	player_registered.emit(id, pname, pchar)


@rpc("any_peer", "call_remote", "unreliable")
func _ping(t: int) -> void:
	_pong.rpc_id(multiplayer.get_remote_sender_id(), t)


@rpc("authority", "call_remote", "unreliable")
func _pong(t: int) -> void:
	ping_ms = Time.get_ticks_msec() - t

