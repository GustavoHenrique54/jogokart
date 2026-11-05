@tool
extends EditorPlugin
## Plugin de Editor para:
## 1. Mostrar um contador de FPS ao vivo na barra superior do Editor 3D e ativar o
##    "View Frame Time (FPS)" nativo do Viewport 3D.
## 2. Aumentar a velocidade base de voo da câmera 3D (freelook_base_speed = 65 m/s)
##    para que uma pista de 4 km não pareça "travada" ao navegar com WASD / Scroll.
## 3. Botão rápido na barra do 3D para Teletransportar a Câmera para a Largada ou para
##    o ponto selecionado da pista.

var _fps_label: Label
var _cam_btn: Button
var _timer := 0.0


func _enter_tree() -> void:
	# Ajusta EditorSettings para pistas grandes em 3D
	var es := EditorInterface.get_editor_settings()
	if es:
		es.set_setting("editors/3d/freelook/freelook_base_speed", 65.0)
		es.set_setting("editors/3d/grid_size", 50)
		es.set_setting("editors/3d_gizmos/gizmo_settings/show_collision_shapes_only_when_selected", true)

	# Cria barra de FPS + atalho de câmera no topo do Viewport 3D
	_fps_label = Label.new()
	_fps_label.text = " Viewport FPS: -- "
	_fps_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.45))
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _fps_label)

	_cam_btn = Button.new()
	_cam_btn.text = "Ir p/ Largada"
	_cam_btn.tooltip_text = "Move a câmera do Viewport 3D direto para a largada da pista e corrige o zoom/órbita"
	_cam_btn.pressed.connect(_focus_start_of_track)
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _cam_btn)


func _exit_tree() -> void:
	if _fps_label:
		remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _fps_label)
		_fps_label.queue_free()
	if _cam_btn:
		remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _cam_btn)
		_cam_btn.queue_free()


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= 0.25 and _fps_label:
		_timer = 0.0
		var fps := Engine.get_frames_per_second()
		var cam := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
		var pos_str := ""
		if cam:
			pos_str = " | Cam: (%d, %d, %d)" % [ int(cam.global_position.x), int(cam.global_position.y), int(cam.global_position.z) ]
		_fps_label.text = "  FPS: %d%s  " % [fps, pos_str]
		if fps >= 50:
			_fps_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.45))
		elif fps >= 30:
			_fps_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
		else:
			_fps_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))


func _focus_start_of_track() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	var path := root.find_child("TrackPath", true, false) as Path3D
	if path and path.curve and path.curve.point_count > 0:
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(path)
		var vp := EditorInterface.get_editor_viewport_3d(0)
		var cam := vp.get_camera_3d()
		if cam:
			var p0 := path.to_global(path.curve.get_point_position(0))
			cam.global_position = p0 + Vector3(-25, 22, -25)
			cam.look_at(p0 + Vector3(30, -4, 0), Vector3.UP)

