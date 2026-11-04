extends Node3D
## Cena principal: liga UI <-> rede e faz o spawn dos karts.

const KART_SCENE := preload("res://scenes/kart.tscn")

@onready var world: Node3D = $World
@onready var karts: Node3D = $Karts
@onready var spawner: MultiplayerSpawner = $KartSpawner
@onready var ui: CanvasLayer = $UI

var _slots := {} ## peer_id -> slot (só no servidor)


func _ready() -> void:
	spawner.spawn_function = _spawn_kart
	Net.player_registered.connect(_on_player_registered)
	Net.player_left.connect(_on_player_left)
	Net.session_started.connect(ui.show_hud)
	Net.session_ended.connect(_on_session_ended)

	ui.join_requested.connect(func(addr: String, pname: String):
		Net.player_name = pname
		Net.join(addr))
	ui.host_requested.connect(func(pname: String):
		Net.player_name = pname
		Net.host(Net.DEFAULT_PORT, false))
	ui.practice_requested.connect(func(pname: String):
		Net.player_name = pname
		Net.start_offline())
	ui.leave_requested.connect(func(): Net.leave())

	if Net.wants_dedicated_server():
		ui.visible = false
		Net.host(Net.cmdline_port(), true)
	elif "--practice" in OS.get_cmdline_user_args() or "--practice" in OS.get_cmdline_args():
		Net.start_offline()


func _on_player_registered(id: int, pname: String) -> void:
	if karts.has_node(str(id)):
		return
	var slot := 0
	while slot in _slots.values():
		slot += 1
	_slots[id] = slot
	spawner.spawn({"id": id, "name": pname, "slot": slot})


func _on_player_left(id: int) -> void:
	_slots.erase(id)
	var k := karts.get_node_or_null(str(id))
	if k:
		k.queue_free()


func _on_session_ended(reason: String) -> void:
	_slots.clear()
	for c in karts.get_children():
		c.queue_free()
	ui.show_menu(reason)


## Roda em TODOS os peers (servidor e clientes) com os mesmos dados.
func _spawn_kart(data: Variant) -> Node:
	var k: Kart = KART_SCENE.instantiate()
	k.peer_id = data["id"]
	k.player_name = data["name"]
	k.slot = data["slot"]
	k.name = str(data["id"])
	var sp: Dictionary = world.get_spawn_point(data["slot"])
	k.spawn_pos = sp["pos"]
	k.spawn_heading = sp["heading"]
	return k

