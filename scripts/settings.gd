extends Node
## Preferências do jogador (autoload "Settings"), salvas em user://settings.cfg.
## Mantém as mesmas chaves que a versão anterior do menu usava, então ninguém perde o que já salvou.

signal changed

const PATH := "user://settings.cfg"
const UI_SCALES := [0.9, 1.0, 1.15, 1.3]
const TOUCH_SCALES := [0.85, 1.0, 1.18]
const RESOLUTIONS := [Vector2i(1920, 1080), Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(1024, 576)]

var player_name := ""
var character := "boitata"
var last_address := ""
var master_volume := 0.8
var fullscreen := false
var resolution_index := 2
var ui_scale := 1.0
var camera_shake := true
var show_stats := false
var touch_scale := 1.0
var best_time := 0.0


func _ready() -> void:
	var had_file := load_settings()
	apply()
	if had_file:
		apply_video()


func load_settings() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return false
	player_name = cfg.get_value("player", "name", "")
	character = cfg.get_value("player", "character", "boitata")
	last_address = cfg.get_value("net", "address", "")
	master_volume = cfg.get_value("audio", "master_volume", 0.8)
	fullscreen = cfg.get_value("video", "fullscreen", false)
	resolution_index = cfg.get_value("video", "resolution_index", 2)
	ui_scale = cfg.get_value("video", "ui_scale", 1.0)
	camera_shake = cfg.get_value("video", "camera_shake", true)
	show_stats = cfg.get_value("video", "show_stats", false)
	touch_scale = cfg.get_value("touch", "scale", 1.0)
	best_time = cfg.get_value("records", "best_time", 0.0)
	return true


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "character", character)
	cfg.set_value("net", "address", last_address)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "resolution_index", resolution_index)
	cfg.set_value("video", "ui_scale", ui_scale)
	cfg.set_value("video", "camera_shake", camera_shake)
	cfg.set_value("video", "show_stats", show_stats)
	cfg.set_value("touch", "scale", touch_scale)
	cfg.set_value("records", "best_time", best_time)
	cfg.save(PATH)
	apply()
	changed.emit()


## Escala da interface + volume (barato, pode rodar a cada mudança).
func apply() -> void:
	get_tree().root.content_scale_factor = ui_scale
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_mute(bus, master_volume <= 0.001)
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(master_volume, 0.0001)))
	Net.player_character = character


## Janela/tela cheia/resolução — só no desktop.
func apply_video() -> void:
	if not can_change_window():
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var res: Vector2i = RESOLUTIONS[clampi(resolution_index, 0, RESOLUTIONS.size() - 1)]
		DisplayServer.window_set_size(res)
		var screen := DisplayServer.screen_get_size()
		DisplayServer.window_set_position((screen - res) / 2)


func can_change_window() -> bool:
	return DisplayServer.get_name() != "headless" and not OS.has_feature("web") and not OS.has_feature("mobile")


## Retorna true se for um novo recorde.
func submit_time(t: float) -> bool:
	if t <= 0.0:
		return false
	if best_time <= 0.0 or t < best_time:
		best_time = t
		save_settings()
		return true
	return false
