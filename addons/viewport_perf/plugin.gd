@tool
extends EditorPlugin
## Plugin de Editor para:
## 1. Sincronização Ao Vivo Blender <-> Godot (.blend):
##    - Configura automaticamente o caminho do Blender (`F:/blender/blender.exe`).
##    - Monitora continuamente em segundo plano (mesmo quando você está com a janela do Blender focada!)
##      a data de modificação do arquivo `.blend` da pista (`res://maps/pista_floresta.blend` ou qualquer
##      outro `.blend` na pasta `res://maps/`).
##    - No exato instante em que você aperta `Ctrl + S` no Blender, dispara a reimportação do Godot
##      e atualiza a pista ao vivo no Viewport 3D!
## 2. Botões rápidos na barra superior do Viewport 3D:
##    - `🎨 Editar no Blender` (abre o `.blend` da pista direto no Blender)
##    - `Ir p/ Largada`
##    - Contador de FPS e coordenadas da câmera ao vivo.

const BLENDER_EXE := "F:/blender/blender.exe"

var _fps_label: Label
var _cam_btn: Button
var _blender_btn: Button
var _timer := 0.0
var _watch_timer := 0.0
var _watched_mtimes: Dictionary = {} # res_path -> int (unix mtime)
var _pending_world_reload := false


func _enter_tree() -> void:
	var es := EditorInterface.get_editor_settings()
	if es:
		es.set_setting("editors/3d/freelook/freelook_base_speed", 65.0)
		es.set_setting("editors/3d/grid_size", 50)
		es.set_setting("editors/3d_gizmos/gizmo_settings/show_collision_shapes_only_when_selected", true)
		if FileAccess.file_exists(BLENDER_EXE):
			es.set_setting("filesystem/import/blender/blender_path", BLENDER_EXE)
			es.set_setting("filesystem/external_programs/3d_model_editor", BLENDER_EXE)

	var efs := EditorInterface.get_resource_filesystem()
	if efs and not efs.resources_reimported.is_connected(_on_resources_reimported):
		efs.resources_reimported.connect(_on_resources_reimported)

	_fps_label = Label.new()
	_fps_label.text = " Viewport FPS: -- "
	_fps_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.45))
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _fps_label)

	_cam_btn = Button.new()
	_cam_btn.text = "Ir p/ Largada"
	_cam_btn.tooltip_text = "Move a câmera do Viewport 3D direto para a largada da pista"
	_cam_btn.pressed.connect(_focus_start_of_track)
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _cam_btn)

	_blender_btn = Button.new()
	_blender_btn.text = "Editar Pista no Blender (.blend)"
	_blender_btn.tooltip_text = "Abre o arquivo .blend do mapa no Blender. Ao salvar (Ctrl+S) lá no Blender, a pista atualiza ao vivo aqui no Godot!"
	_blender_btn.pressed.connect(_open_current_map_in_blender)
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _blender_btn)

	_snapshot_blend_mtimes()


func _exit_tree() -> void:
	var efs := EditorInterface.get_resource_filesystem()
	if efs and efs.resources_reimported.is_connected(_on_resources_reimported):
		efs.resources_reimported.disconnect(_on_resources_reimported)

	for ctrl in [_fps_label, _cam_btn, _blender_btn]:
		if ctrl:
			remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, ctrl)
			ctrl.queue_free()


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= 0.25 and _fps_label:
		_timer = 0.0
		var fps := Engine.get_frames_per_second()
		var cam := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
		var pos_str := ""
		if cam:
			pos_str = " | Cam: (%d, %d, %d)" % [int(cam.global_position.x), int(cam.global_position.y), int(cam.global_position.z)]
		_fps_label.text = "  FPS: %d%s  " % [fps, pos_str]
		if fps >= 50:
			_fps_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.45))
		elif fps >= 30:
			_fps_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
		else:
			_fps_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))

	# Monitora arquivos .blend a cada 0.5s (funciona mesmo com o Godot em segundo plano enquanto você usa o Blender!)
	_watch_timer += delta
	if _watch_timer >= 0.5:
		_watch_timer = 0.0
		_check_blend_files_modified()


func _get_world_node() -> Node3D:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	if root.name == "World":
		return root as Node3D
	return root.find_child("World", true, false) as Node3D


func _get_watched_blend_paths() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open("res://maps")
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and (fname.ends_with(".blend") or fname.ends_with(".glb")):
				paths.append("res://maps/" + fname)
			fname = dir.get_next()
		dir.list_dir_end()
	var w := _get_world_node()
	if w and "blender_map_file" in w:
		var bfile := str(w.get("blender_map_file"))
		if bfile != "" and not (bfile in paths):
			paths.append(bfile)
	return paths


func _snapshot_blend_mtimes() -> void:
	for p in _get_watched_blend_paths():
		var abs_p := ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(abs_p):
			_watched_mtimes[p] = FileAccess.get_modified_time(abs_p)


func _check_blend_files_modified() -> void:
	var efs := EditorInterface.get_resource_filesystem()
	if efs == null or efs.is_scanning():
		return
	var changed := false
	for p in _get_watched_blend_paths():
		var abs_p := ProjectSettings.globalize_path(p)
		if not FileAccess.file_exists(abs_p):
			continue
		var mtime := FileAccess.get_modified_time(abs_p)
		var prev_mtime: int = _watched_mtimes.get(p, 0)
		if prev_mtime == 0:
			_watched_mtimes[p] = mtime
		elif mtime > prev_mtime:
			_watched_mtimes[p] = mtime
			changed = true
			print("[BlenderSync] Salvamento detectado no Blender (%s)! Atualizando pista no Godot..." % p)

	if changed:
		_pending_world_reload = true
		efs.scan()


func _on_resources_reimported(resources: PackedStringArray) -> void:
	var has_map := _pending_world_reload
	for r in resources:
		if r.ends_with(".blend") or r.ends_with(".glb") or r.ends_with(".fbx"):
			has_map = true
			break
	if has_map:
		_pending_world_reload = false
		var w := _get_world_node()
		if w and w.has_method("reload_blender_map"):
			w.call_deferred("reload_blender_map")


func _open_current_map_in_blender() -> void:
	var w := _get_world_node()
	if w and w.has_method("open_map_in_blender"):
		w.call("open_map_in_blender")
	elif FileAccess.file_exists(BLENDER_EXE):
		var abs_blend := ProjectSettings.globalize_path("res://maps/pista_floresta.blend")
		OS.create_process(BLENDER_EXE, [abs_blend])


func _focus_start_of_track() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	var vp := EditorInterface.get_editor_viewport_3d(0)
	var cam := vp.get_camera_3d()
	if cam == null:
		return
	var w := _get_world_node()
	if w and w.has_method("get_spawn_point"):
		var sp: Dictionary = w.call("get_spawn_point", 0)
		var p0: Vector3 = sp.get("pos", Vector3(-540, 2, 0))
		cam.global_position = p0 + Vector3(-25, 22, -25)
		cam.look_at(p0 + Vector3(30, -4, 0), Vector3.UP)
		return
	var path := root.find_child("TrackPath", true, false) as Path3D
	if path and path.curve and path.curve.point_count > 0:
		var p0 := path.to_global(path.curve.get_point_position(0))
		cam.global_position = p0 + Vector3(-25, 22, -25)
		cam.look_at(p0 + Vector3(30, -4, 0), Vector3.UP)
