@tool
class_name TrackZone
extends Node3D
## Volume 3D de esculpir relevo na pista (funciona como um Brush/Lattice no Viewport 3D!).
##
## Como usar:
## - Selecione ou duplique (Ctrl+D) um nó `TrackZone` dentro de `World/TrackZones`.
## - Mova (W), gire (E) e ajuste `depth_offset`, `zone_width` e `zone_length` no Inspector:
##   * `depth_offset < 0` (ex: -2.2): afunda a rua naquele ponto (cria um DECLIVE forte AZUL!).
##   * `depth_offset > 0` (ex: +1.8): levanta a rua naquele ponto (cria uma LOMBADA / ACLIVE LARANJA!).
## - A pista reconstrói automaticamente no Viewport 3D enquanto você move ou edita!

@export_range(-8.0, 8.0, 0.1) var depth_offset := -2.2:
	set(v):
		depth_offset = v
		_update_gizmo()
		_notify_world()

@export_range(2.0, 30.0, 0.5) var zone_width := 5.5:
	set(v):
		zone_width = maxf(v, 1.5)
		_update_gizmo()
		_notify_world()

@export_range(3.0, 60.0, 0.5) var zone_length := 16.0:
	set(v):
		zone_length = maxf(v, 2.0)
		_update_gizmo()
		_notify_world()

var _preview_mesh: MeshInstance3D
var _last_xform: Transform3D


func _ready() -> void:
	set_notify_transform(true)
	_last_xform = global_transform
	if Engine.is_editor_hint():
		_update_gizmo()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		if global_transform != _last_xform:
			_last_xform = global_transform
			_notify_world()


func _update_gizmo() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _preview_mesh == null:
		_preview_mesh = MeshInstance3D.new()
		_preview_mesh.name = "_PreviewGizmo"
		_preview_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_preview_mesh)
	var bm := CylinderMesh.new()
	bm.top_radius = 1.0
	bm.bottom_radius = 1.0
	bm.height = maxf(absf(depth_offset), 0.4)
	bm.radial_segments = 16
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if depth_offset < 0.0:
		mat.albedo_color = Color(0.1, 0.75, 1.0, 0.28)
	else:
		mat.albedo_color = Color(1.0, 0.45, 0.1, 0.28)
	bm.material = mat
	_preview_mesh.mesh = bm
	_preview_mesh.scale = Vector3(zone_width, 1.0, zone_length)
	_preview_mesh.position = Vector3(0.0, depth_offset * 0.5, 0.0)


func _notify_world() -> void:
	if not is_inside_tree():
		return
	var p := get_parent()
	while p != null:
		if p.has_method("_queue_rebuild"):
			p.call("_queue_rebuild")
			return
		p = p.get_parent()

