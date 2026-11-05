extends Node3D
## Cena principal: liga UI <-> rede e faz o spawn dos karts.

const KART_SCENE := preload("res://scenes/kart.tscn")
const RACE_MANAGER_SCRIPT := preload("res://scripts/race_manager.gd")

@onready var world: Node3D = $World
@onready var karts: Node3D = $Karts
@onready var spawner: MultiplayerSpawner = $KartSpawner
@onready var ui: CanvasLayer = $UI

var _slots := {} ## peer_id -> slot (só no servidor)
var race_manager: Node


func _ready() -> void:
	race_manager = RACE_MANAGER_SCRIPT.new()
	race_manager.name = "RaceManager"
	add_child(race_manager)

	spawner.spawn_function = _spawn_kart
	Net.player_registered.connect(_on_player_registered)
	Net.player_left.connect(_on_player_left)
	Net.session_started.connect(_on_session_started)
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

	# Câmera que passeia pela pista atrás dos menus.
	var menu_cam := MenuCamera.new()
	menu_cam.world = world
	add_child(menu_cam)
	ui.menu_camera = menu_cam
	menu_cam.activate()

	var shot := _arg_value("--ui-shot=")
	if shot != "":
		if "--fake-touch" in OS.get_cmdline_user_args():
			GameInput.force_device(GameInput.Device.TOUCH)
		elif "--fake-gamepad" in OS.get_cmdline_user_args():
			GameInput.force_device(GameInput.Device.GAMEPAD)
		ui.debug_capture(shot, _arg_value("--shot-out="))
		return

	if Net.wants_dedicated_server():
		ui.visible = false
		Net.host(Net.cmdline_port(), true)
	elif "--bake-editor-scene" in OS.get_cmdline_user_args() or "--bake-editor-scene" in OS.get_cmdline_args():
		_bake_editor_scene()
	elif "--practice" in OS.get_cmdline_user_args() or "--practice" in OS.get_cmdline_args():
		Net.start_offline()


func _arg_value(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""


func _on_player_registered(id: int, pname: String, pchar: String = "boitata") -> void:
	if karts.has_node(str(id)):
		return
	var slot := 0
	while slot in _slots.values():
		slot += 1
	_slots[id] = slot
	spawner.spawn({"id": id, "name": pname, "slot": slot, "character": pchar})


func _on_player_left(id: int) -> void:
	_slots.erase(id)
	var k := karts.get_node_or_null(str(id))
	if k:
		k.queue_free()


func _on_session_started() -> void:
	ui.show_hud()
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		# Breve tempo para o kart se posicionar no grid de largada antes da contagem
		get_tree().create_timer(0.6).timeout.connect(func():
			if Net.in_session and race_manager:
				race_manager.start_countdown()
		)


func _on_session_ended(reason: String) -> void:
	if race_manager:
		race_manager.reset_race()
	_slots.clear()
	for c in karts.get_children():
		c.queue_free()
	ui.show_menu(reason)


## Roda em TODOS os peers (servidor e clientes) com os mesmos dados.
func _spawn_kart(data: Variant) -> Node:
	var k: Kart = KART_SCENE.instantiate()
	k.peer_id = data["id"]
	k.player_name = data["name"]
	k.character_id = data.get("character", "boitata")
	k.slot = data["slot"]
	k.name = str(data["id"])
	var sp: Dictionary = world.get_spawn_point(data["slot"])
	k.spawn_pos = sp["pos"]
	k.spawn_heading = sp["heading"]
	return k


func _bake_editor_scene() -> void:
	world._ensure_editor_nodes()
	world.reset_default_curve()
	world._apply_editor_perf_settings()
	var sc := world.get_node_or_null("Scenery")
	if sc:
		for c in sc.get_children():
			c.free()
	var gen := world.get_node_or_null("GeneratedTrack")
	if gen:
		gen.free()
	for child_name in ["WorldEnvironment", "Sun", "TrackPath", "TrackZones", "Scenery"]:
		var n := world.get_node_or_null(child_name)
		if n:
			n.owner = self
			for sub in n.get_children():
				sub.owner = self
				for sub2 in sub.get_children():
					sub2.owner = self
	var out := PackedScene.new()
	out.pack(self)
	ResourceSaver.save(out, "res://scenes/main.tscn")
	print("[Main] CENA SALVA LEVE E OTIMIZADA!")
	get_tree().quit(0)

