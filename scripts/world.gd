@tool
extends Node3D
## Pista de Descida de Morro (Rolimã Pumptrack) — Suporte Total a Edição Ao Vivo no Blender (.blend)!
##
## Como funciona o fluxo Blender <-> Godot Ao Vivo:
## 1. Quando `use_blender_map = true`, o nó `World` carrega diretamente o arquivo `.blend` configurado
##    em `blender_map_file` (por padrão `res://maps/pista_floresta.blend`).
## 2. A textura da estrada no Blender fica 100% limpa (apenas a textura de terra/cascalho).
## 3. O Godot calcula dinamicamente a inclinação real da malha 3D esculpida no Blender e projeta
##    por cima uma camada/textura transparente (`SlopeOverlay`) destacando:
##    - Grandes Declives (bolsões de impulso): Azul-Ciano translúcido
##    - Grandes Aclives (rampas / lombadas de salto): Laranja translúcido
## 4. Assim que você salva (`Ctrl + S`) no Blender, tanto o relevo físico quanto as marcações
##    translúcidas de aclive/declive atualizam ao vivo no Godot!

const BLENDER_EXE_PATH := "F:/blender/blender.exe"
const DEFAULT_BLEND_MAP := "res://maps/pista_floresta.blend"

@export_group("Edição Ao Vivo no Blender (.blend)")
@export var use_blender_map := true: ## Quando ativo, usa o arquivo .blend abaixo (atualiza ao vivo ao salvar Ctrl+S no Blender!)
	set(v):
		use_blender_map = v
		_queue_rebuild()
@export_file("*.blend", "*.glb", "*.gltf", "*.fbx", "*.tscn") var blender_map_file := DEFAULT_BLEND_MAP:
	set(v):
		blender_map_file = v
		_blend_last_mtime = 0
		_queue_rebuild()
@export var show_dynamic_slope_overlay := true: ## Mostra a textura translúcida laranja (aclive) e azul (declive) calculada dinamicamente sobre a malha esculpida
	set(v):
		show_dynamic_slope_overlay = v
		_queue_rebuild()
@export_range(0.02, 0.35, 0.01) var slope_highlight_threshold := 0.17: ## Sensibilidade para destacar grandes declives (azul) e grandes aclives (laranja)
	set(v):
		slope_highlight_threshold = v
		_queue_rebuild()
@export_range(0.1, 1.0, 0.05) var slope_overlay_opacity := 0.65: ## Opacidade máxima da textura translúcida de aclive/declive
	set(v):
		slope_overlay_opacity = v
		_queue_rebuild()
@export var apply_psx_retro_filter := true: ## Aplica filtro pixelado PS1 (Nearest) nos materiais vindos do Blender
	set(v):
		apply_psx_retro_filter = v
		_queue_rebuild()
@export_tool_button("Abrir Mapa Atual no Blender") var btn_open_blender := open_map_in_blender
@export_tool_button("Recarregar .blend Agora") var btn_reload_blend := reload_blender_map
@export_tool_button("Exportar Pista Procedural p/ .blend") var btn_export_blend := export_procedural_to_blend

@export_group("Estilo Visual Retrô (PS1 / N64)")
@export var night_mode := false: ## Alterna entre o céu DAYSKY.hdr (dia tropical) e PSX_NIGHTSKY.hdr (noite)
	set(v):
		night_mode = v
		_apply_editor_perf_settings()
@export var editor_fast_mode := false:
	set(v):
		editor_fast_mode = v
		_apply_editor_perf_settings()
		_queue_rebuild()
@export var show_trees_in_editor := true:
	set(v):
		show_trees_in_editor = v
		_queue_rebuild()

@export_group("Gerador Procedural (Base para novos .blend)")
@export_tool_button("Reconstruir Pista Procedural") var btn_rebuild := rebuild_track
@export_tool_button("Resetar Curva Padrão no TrackPath") var btn_reset_curve := reset_default_curve
@export var half_width := 10.5:
	set(v):
		half_width = maxf(v, 3.0)
		_queue_rebuild()
@export var terrain_skirt_width := 52.0:
	set(v):
		terrain_skirt_width = maxf(v, 12.0)
		_queue_rebuild()
@export var curb_width := 1.1:
	set(v):
		curb_width = maxf(v, 0.2)
		_queue_rebuild()
@export var curb_height := 0.85:
	set(v):
		curb_height = maxf(v, 0.0)
		_queue_rebuild()
@export var cross_slices := 10:
	set(v):
		cross_slices = clampi(v, 4, 24)
		_queue_rebuild()
@export var sample_step := 2.8:
	set(v):
		sample_step = clampf(v, 1.5, 12.0)
		_queue_rebuild()
@export var procedural_waves_intensity := 1.0:
	set(v):
		procedural_waves_intensity = clampf(v, 0.0, 3.0)
		_queue_rebuild()
@export var lateral_pockets_intensity := 1.0:
	set(v):
		lateral_pockets_intensity = clampf(v, 0.0, 3.0)
		_queue_rebuild()
@export var crest_bumps_intensity := 1.0:
	set(v):
		crest_bumps_intensity = clampf(v, 0.0, 3.0)
		_queue_rebuild()

const TRACK_ZONE_SCRIPT := preload("res://scripts/track_zone.gd")

# Caminhos dos Assets Retrô (PS1 / N64)
const HDRI_DAY_PATH := "res://Assets/PSX_Daysky_HDRI/DAYSKY.hdr"
const HDRI_NIGHT_PATH := "res://Assets/PSX_Nightsky_HDRI/PSX_NIGHTSKY.hdr"
const TEX_ROAD_EARTH := "res://Assets/PSX_Forest_Level_byStarkCrafts/PSX_ForestGround_Tex/PSX_Seamless_ForestEarthGround_128px.png"
const TEX_ROAD_GRAVEL := "res://Assets/PSX_Forest_Level_byStarkCrafts/PSX_ForestGround_Tex/PSX_Seamless_ForestGravel_Ground_128px.png"
const TEX_JUNGLE_GRASS := "res://Assets/PSX_Forest_Level_byStarkCrafts/PSX_ForestGround_Tex/PSX_Seamless_WildForestGrass_128px.png"
const TEX_JUNGLE_CLOVER := "res://Assets/PSX_Forest_Level_byStarkCrafts/PSX_ForestGround_Tex/PSX_Seamless_WildForestClover_128px.png"
const TEX_PS1_WOOD := "res://Assets/textures/Ps1Wood_baseColor.png"

const RETRO_TREE_GLBS := [
	"res://Assets/Retro Tree Pack v1.0/Retro Tree Pack/Models/Super Low Res/GLB/tree_rt_1.glb",
	"res://Assets/Retro Tree Pack v1.0/Retro Tree Pack/Models/Super Low Res/GLB/tree_rt_2.glb",
	"res://Assets/Retro Tree Pack v1.0/Retro Tree Pack/Models/Super Low Res/GLB/tree_rt_3.glb",
	"res://Assets/Retro Tree Pack v1.0/Retro Tree Pack/Models/Super Low Res/GLB/tree_rt_4.glb",
	"res://Assets/Retro Tree Pack v1.0/Retro Tree Pack/Models/Super Low Res/GLB/small_tree_rt_1.glb",
	"res://Assets/Retro Tree Pack v1.0/Retro Tree Pack/Models/Super Low Res/GLB/dead_tree_rt_1.glb",
]
const PSX_FOREST_FBX := "res://Assets/PSX_Forest_Level_byStarkCrafts/PSX_Forest_AssetCollection_byStarkCrafts.fbx"
const PSX_GLTF_SCENE := "res://Assets/scene.gltf"

const CONTROL_POINTS_2D := [
	Vector2(-52, 0),
	Vector2(-15, -2),
	Vector2(35, 0),
	Vector2(68, 12),
	Vector2(76, 30),
	Vector2(62, 42),
	Vector2(52, 26),
	Vector2(28, 18),
	Vector2(4, 24),
	Vector2(-2, 34),
	Vector2(20, 44),
	Vector2(18, 56),
	Vector2(-15, 58),
	Vector2(-48, 56),
	Vector2(-60, 70),
	Vector2(-42, 84),
	Vector2(5, 82),
	Vector2(45, 76),
	Vector2(64, 92),
	Vector2(50, 110),
	Vector2(8, 112),
	Vector2(-35, 110),
	Vector2(-48, 120),
	Vector2(-25, 128),
	Vector2(5, 130),
	Vector2(18, 142),
	Vector2(-5, 152),
	Vector2(-38, 148),
	Vector2(-50, 162),
	Vector2(-30, 176),
	Vector2(15, 174),
	Vector2(55, 168),
	Vector2(72, 180),
	Vector2(52, 194),
	Vector2(10, 192),
	Vector2(-10, 198),
	Vector2(5, 210),
	Vector2(18, 226),
	Vector2(16, 250),
	Vector2(10, 272),
	Vector2(-25, 274),
	Vector2(-58, 282),
	Vector2(-68, 298),
	Vector2(-52, 310),
	Vector2(-5, 308),
	Vector2(18, 318),
	Vector2(26, 338),
	Vector2(26, 355),
]
const WORLD_SCALE := 11.2
const BASE_SLOPE := 0.082

var samples: Array[Dictionary] = []
var total_length := 0.0
var _rebuild_timer := 0.0
var _zones_cache: Array[Dictionary] = []
var _mesh_cache: Dictionary = {}
var _packed_cache: Dictionary = {}
var _overlay_pattern_tex: ImageTexture = null

# Estado do mapa carregado via Blender (.blend)
var _using_active_blender_map := false
var _force_replace_cache := false
var _blend_last_mtime: int = 0
var _blender_spawn_pos := Vector3(-541.9, -2.5, -1.9)
var _blender_spawn_fwd := Vector3(0.998, 0.0, -0.055)
var _blender_spawn_right := Vector3(0.055, 0.0, 0.998)
var _blender_finish_pos := Vector3(291.2, -320.0, 3942.0)
var _blender_finish_fwd := Vector3(0.0, 0.0, 1.0)
var _road_meshes_for_spawn: Array[MeshInstance3D] = []


func _ready() -> void:
	_ensure_editor_nodes()
	_apply_editor_perf_settings()
	if "--export-blend-track" in OS.get_cmdline_user_args() or "--export-blend-track" in OS.get_cmdline_args():
		export_procedural_to_blend()
		if DisplayServer.get_name() == "headless":
			get_tree().quit(0)
			return
	rebuild_track()


func _process(delta: float) -> void:
	if _rebuild_timer > 0.0:
		_rebuild_timer -= delta
		if _rebuild_timer <= 0.0:
			rebuild_track()


func _queue_rebuild() -> void:
	if not is_inside_tree():
		return
	_rebuild_timer = 0.12 if Engine.is_editor_hint() else 0.01


# ----------------------------------------------------------------- Integração Ao Vivo com o Blender (.blend)

## Abre o arquivo `.blend` atual diretamente no Blender 5.2 para você modelar/esculpir a pista!
func open_map_in_blender() -> void:
	var target_res := blender_map_file if blender_map_file != "" else DEFAULT_BLEND_MAP
	var abs_blend := ProjectSettings.globalize_path(target_res)
	if not FileAccess.file_exists(abs_blend):
		print("[BlenderSync] Arquivo .blend ainda não existe em %s — gerando agora a partir da pista atual..." % abs_blend)
		export_procedural_to_blend()
	if FileAccess.file_exists(BLENDER_EXE_PATH):
		OS.create_process(BLENDER_EXE_PATH, [abs_blend])
		print("[BlenderSync] Abrindo no Blender: ", abs_blend)
	else:
		OS.shell_open(abs_blend)


## Chamado automaticamente pelo plugin quando você aperta `Ctrl + S` no Blender (ou pelo botão no Inspector).
func reload_blender_map() -> void:
	_force_replace_cache = true
	rebuild_track()
	print("[BlenderSync] Mapa .blend e marcações dinâmicas de aclive/declive recarregados ao vivo: ", blender_map_file)


## Exporta a pista procedural atual (malha única contínua da rua SEM cores de aclive/declive fixas + terreno + largada/chegada + vegetação)
## diretamente para um arquivo `.blend` editável no Blender (`res://maps/pista_floresta.blend`).
func export_procedural_to_blend() -> void:
	_ensure_editor_nodes()
	_cache_track_zones()
	_generate_centerline_from_path()

	var target_res := blender_map_file if blender_map_file.ends_with(".blend") else DEFAULT_BLEND_MAP
	var abs_blend := ProjectSettings.globalize_path(target_res)
	var temp_glb := ProjectSettings.globalize_path("user://temp_track_export.glb")
	var script_py := ProjectSettings.globalize_path("res://tools/build_blend_from_glb.py")

	print("[BlenderSync] Construindo malha contínua da pista (textura limpa) e floresta para exportar ao Blender...")
	var export_root := Node3D.new()
	export_root.name = "GeneratedExport"
	add_child(export_root)

	# Na exportação para o Blender, a estrada usa apenas a textura pura (sem vertex colors de inclinação)
	var road_mat := _make_psx_material(TEX_ROAD_GRAVEL, false, 0.9)
	var jungle_mat := _make_psx_material(TEX_JUNGLE_GRASS, true, 0.96)

	_build_single_chunk(export_root, 0, samples.size() - 1, road_mat, jungle_mat, true)
	_build_start_and_finish_banners(export_root, true)
	_build_combined_forest_for_export(export_root)

	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	var err := gltf_doc.append_from_scene(export_root, gltf_state)
	if err == OK:
		err = gltf_doc.write_to_filesystem(gltf_state, temp_glb)
	export_root.free()

	if err != OK:
		push_error("[BlenderSync] Erro ao exportar GLB intermediário: %d" % err)
		return

	print("[BlenderSync] Convertendo para arquivo nativo do Blender (.blend) via %s ..." % BLENDER_EXE_PATH)
	var out_lines := []
	var exit_code := OS.execute(BLENDER_EXE_PATH, ["-b", "-P", script_py, "--", temp_glb, abs_blend], out_lines, true)
	if exit_code != 0:
		push_error("[BlenderSync] Falha ao rodar Blender CLI (código %d): %s" % [exit_code, "\n".join(out_lines)])
		return

	print("[BlenderSync] Arquivo .blend criado com sucesso em: ", abs_blend)
	if Engine.is_editor_hint() and Engine.has_singleton("EditorInterface"):
		var ei: Object = Engine.get_singleton("EditorInterface")
		var efs: Object = ei.call("get_resource_filesystem")
		if efs:
			efs.call("scan")


func _load_from_blender_map(gen: Node3D) -> bool:
	if blender_map_file == "" or not ResourceLoader.exists(blender_map_file):
		return false

	var mode := ResourceLoader.CACHE_MODE_REPLACE if _force_replace_cache else ResourceLoader.CACHE_MODE_REUSE
	_force_replace_cache = false
	var packed := ResourceLoader.load(blender_map_file, "", mode) as PackedScene
	if packed == null:
		return false

	var map_inst := packed.instantiate() as Node3D
	if map_inst == null:
		return false
	map_inst.name = "BlenderMap"
	gen.add_child(map_inst)
	_road_meshes_for_spawn.clear()

	# Esconde os gizmos procedurais antigos quando estamos usando o mapa do Blender
	var path_node := get_node_or_null("TrackPath") as Node3D
	if path_node:
		path_node.visible = false
	var zones_node := get_node_or_null("TrackZones") as Node3D
	if zones_node:
		zones_node.visible = false

	var found_spawn := false
	var found_finish := false
	var highest_v := Vector3(0.0, -999999.0, 0.0)
	var lowest_v := Vector3(0.0, 999999.0, 0.0)

	# Percorre todos os nós vindos do arquivo .blend
	var all_nodes: Array[Node] = [map_inst]
	var idx := 0
	while idx < all_nodes.size():
		var cur := all_nodes[idx]
		idx += 1
		for ch in cur.get_children():
			all_nodes.append(ch)

		if cur is Node3D:
			var n3 := cur as Node3D
			var nm_low := n3.name.to_lower()
			# Importante: só captura o nó principal "Largada" / "Spawn" (e NÃO os filhos Largada_PilarEsq, Largada_Faixa, etc.)
			if nm_low == "largada" or nm_low == "spawn":
				found_spawn = true
				_blender_spawn_pos = n3.position
				# No _build_arch, -Z do arco aponta para a frente da descida (s["fwd"])
				var bfwd := -n3.transform.basis.z
				bfwd.y = 0.0
				if bfwd.length_squared() > 0.001:
					_blender_spawn_fwd = bfwd.normalized()
					if samples.size() > 3 and _blender_spawn_pos.distance_to(samples[3]["pos"]) < 80.0:
						if _blender_spawn_fwd.dot(samples[3]["fwd"]) < 0.0:
							_blender_spawn_fwd = -_blender_spawn_fwd
				elif samples.size() > 3:
					_blender_spawn_fwd = samples[3]["fwd"]
				_blender_spawn_right = Vector3(-_blender_spawn_fwd.z, 0.0, _blender_spawn_fwd.x)
				_ensure_arch_label(n3, "LARGADA — SELVA TROPICAL!")
			elif nm_low == "chegada" or nm_low == "finish":
				found_finish = true
				_blender_finish_pos = n3.position
				var ffwd := -n3.transform.basis.z
				ffwd.y = 0.0
				if ffwd.length_squared() > 0.001:
					_blender_finish_fwd = ffwd.normalized()
				elif samples.size() > 4:
					_blender_finish_fwd = samples[samples.size() - 4]["fwd"]
				_ensure_arch_label(n3, "CHEGADA!")

		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if mi.mesh == null:
				continue
			var m_name := mi.name.to_lower()
			var is_foliage := (
				m_name.contains("floresta_") or m_name.contains("arvore") or m_name.contains("tree")
				or m_name.contains("bush") or m_name.contains("arbusto") or m_name.contains("grama")
				or m_name.contains("grass") or m_name.contains("reed") or m_name.contains("lavender")
				or m_name.contains("dandelion") or m_name.contains("sem_colisao") or m_name.contains("nocollide")
			)
			var is_road_mesh := m_name.contains("pista") or m_name.contains("estrada") or m_name.contains("road") or m_name.contains("rua")

			# Aplica filtro retrô PS1 (Nearest Neighbor)
			if apply_psx_retro_filter:
				var mesh_dup := mi.mesh.duplicate() as Mesh
				for s_idx in mesh_dup.get_surface_count():
					var mat := mi.get_active_material(s_idx)
					if mat is BaseMaterial3D:
						var m_copy := mat.duplicate() as BaseMaterial3D
						m_copy.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
						# IMPORTANTE: Na estrada ("Pista_Estrada"), NÃO usamos vertex colors estáticos do Blender!
						# A textura da estrada fica 100% pura, e as marcações laranja/azul vêm da camada translúcida dinâmica!
						if is_road_mesh:
							m_copy.vertex_color_use_as_albedo = false
							m_copy.albedo_color = Color(0.88, 0.82, 0.72)
						elif mesh_dup is ArrayMesh:
							var fmt: int = (mesh_dup as ArrayMesh).surface_get_format(s_idx)
							if (fmt & Mesh.ARRAY_FORMAT_COLOR) != 0:
								m_copy.vertex_color_use_as_albedo = true
						if is_foliage:
							m_copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
							m_copy.alpha_scissor_threshold = 0.45
							m_copy.cull_mode = BaseMaterial3D.CULL_DISABLED
						mesh_dup.surface_set_material(s_idx, m_copy)
				mi.mesh = mesh_dup

			if is_road_mesh:
				_road_meshes_for_spawn.append(mi)
				# Reconstrói a linha central (samples) a partir da própria malha esculpida no Blender
				_rebuild_samples_from_road_mesh(mi)
				# Cria a camada translúcida dinâmica de aclives (laranja) e declives (azul) sobre a geometria esculpida!
				if show_dynamic_slope_overlay:
					_build_dynamic_slope_overlay_for_mesh(mi)

			# Calcula extremos da malha caso seja um mapa novo sem marcador "Largada"/"Chegada"
			if not is_foliage and not m_name.contains("largada") and not m_name.contains("chegada"):
				if _road_meshes_for_spawn.is_empty():
					_road_meshes_for_spawn.append(mi)
				if not found_spawn or not found_finish:
					var aabb := mi.transform * mi.mesh.get_aabb()
					var top_pt := aabb.position + Vector3(aabb.size.x * 0.5, aabb.size.y, aabb.size.z * 0.5)
					var bot_pt := aabb.position + Vector3(aabb.size.x * 0.5, 0.0, aabb.size.z * 0.5)
					if top_pt.y > highest_v.y:
						highest_v = top_pt
					if bot_pt.y < lowest_v.y:
						lowest_v = bot_pt

			# Gera colisão física automaticamente em tempo de jogo para qualquer pista/terreno/rampa modelada no Blender!
			if not Engine.is_editor_hint() and not is_foliage:
				var body := StaticBody3D.new()
				body.collision_layer = 1
				var cs := CollisionShape3D.new()
				var shape := mi.mesh.create_trimesh_shape()
				shape.backface_collision = true
				cs.shape = shape
				body.add_child(cs)
				mi.add_child(body)

	if not found_spawn:
		if samples.size() > 3:
			_blender_spawn_pos = samples[3]["pos"]
			_blender_spawn_fwd = samples[3]["fwd"]
			_blender_spawn_right = samples[3]["right"]
		elif highest_v.y > -99999.0:
			_blender_spawn_pos = highest_v + Vector3(0.0, 1.5, 0.0)
	if not found_finish:
		if samples.size() > 4:
			_blender_finish_pos = samples[samples.size() - 4]["pos"]
			_blender_finish_fwd = samples[samples.size() - 4]["fwd"]
		elif lowest_v.y < 99999.0:
			_blender_finish_pos = lowest_v + Vector3(0.0, 1.5, 0.0)

	# Ajusta a altura Y do ponto de largada exatamente sobre a malha esculpida da estrada!
	var road_y := _sample_road_mesh_height(_blender_spawn_pos.x, _blender_spawn_pos.z, _blender_spawn_pos.y)
	_blender_spawn_pos.y = road_y
	if samples.size() > 4 and _blender_spawn_pos.distance_to(samples[3]["pos"]) < 80.0:
		if _blender_spawn_fwd.dot(samples[3]["fwd"]) < 0.0:
			_blender_spawn_fwd = -_blender_spawn_fwd
			_blender_spawn_right = Vector3(-_blender_spawn_fwd.z, 0.0, _blender_spawn_fwd.x)

	# Cria a área de detecção de chegada em tempo de jogo
	if not Engine.is_editor_hint():
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 2
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(half_width * 2.4, 10.0, 5.0)
		cs.shape = box
		area.add_child(cs)
		var heading := atan2(-_blender_finish_fwd.x, -_blender_finish_fwd.z)
		area.transform = Transform3D(Basis(Vector3.UP, heading), _blender_finish_pos + Vector3.UP * 3.0)
		area.body_entered.connect(_on_finish_entered)
		gen.add_child(area)

	return true


## Reconstrói a linha central (`samples`) diretamente a partir dos vértices e UVs da malha `Pista_Estrada`
## importada do Blender, garantindo que a câmera do menu, o progresso da corrida e o cálculo de direção
## da pista sigam fielmente o traçado real do arquivo `.blend`!
func _rebuild_samples_from_road_mesh(road_mi: MeshInstance3D) -> void:
	if road_mi == null or road_mi.mesh == null or road_mi.mesh.get_surface_count() == 0:
		return
	var arrays := road_mi.mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	if verts.is_empty() or uvs.size() != verts.size():
		return

	var bins_sum: Dictionary = {} # int -> Vector3
	var bins_cnt: Dictionary = {} # int -> int
	var xf := road_mi.transform
	for i in verts.size():
		var uv := uvs[i]
		if uv.x <= 0.31:
			continue # Ignora muretas laterais
		var b_key := roundi(uv.y * 2.0)
		var wp := xf * verts[i]
		if bins_sum.has(b_key):
			bins_sum[b_key] += wp
			bins_cnt[b_key] += 1
		else:
			bins_sum[b_key] = wp
			bins_cnt[b_key] = 1

	if bins_sum.size() < 8:
		return

	var sorted_keys := bins_sum.keys()
	sorted_keys.sort()

	var pts: Array[Vector3] = []
	for k in sorted_keys:
		pts.append((bins_sum[k] as Vector3) / float(bins_cnt[k]))

	# Garante que o índice 0 está no topo da montanha (Largada, maior Y)
	if pts[0].y < pts[pts.size() - 1].y:
		pts.reverse()

	samples.clear()
	var accum_d := 0.0
	for i in pts.size():
		if i > 0:
			accum_d += pts[i].distance_to(pts[i - 1])
		var prev_p := pts[maxi(0, i - 1)]
		var next_p := pts[mini(pts.size() - 1, i + 1)]
		var fwd := next_p - prev_p
		fwd.y = 0.0
		if fwd.length_squared() < 0.0001:
			fwd = Vector3.FORWARD
		else:
			fwd = fwd.normalized()
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		samples.append({
			"pos": pts[i],
			"fwd": fwd,
			"right": right,
			"tilt": 0.0,
			"dist": accum_d,
		})
	total_length = accum_d


## Gera uma textura pixelada 16x16 estilo PS1/N64 com listras translúcidas suaves para a camada
## dinâmica de destaque de grandes aclives (laranja) e grandes declives (azul-ciano).
func _get_slope_overlay_texture() -> ImageTexture:
	if _overlay_pattern_tex != null:
		return _overlay_pattern_tex
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			# Padrão retrô de chevrons/faixas sutis (mantém transparência para ver a textura da rua por baixo!)
			var stripe := ((x + y * 2) % 8) < 6
			var alpha_mul := 1.0 if stripe else 0.72
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha_mul))
	_overlay_pattern_tex = ImageTexture.create_from_image(img)
	return _overlay_pattern_tex


## Calcula dinamicamente a inclinação real de cada vértice/triângulo esculpido no Blender
## e cria uma malha/textura transparente (`SlopeOverlay`) por cima da estrada destacando:
## - Azul-Ciano translúcido onde a rua desce forte (grandes declives / impulso)
## - Laranja translúcido onde a rua sobe ou forma rampa (grandes aclives / salto)
func _build_dynamic_slope_overlay_for_mesh(road_mi: MeshInstance3D) -> void:
	var arr_mesh := road_mi.mesh as ArrayMesh
	if arr_mesh == null or arr_mesh.get_surface_count() == 0:
		return

	var arrays := arr_mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if verts.is_empty():
		return
	var has_uvs := uvs.size() == verts.size()

	# Se a malha não for indexada, gera índices sequenciais
	var tri_indices: PackedInt32Array = indices
	if tri_indices.is_empty():
		tri_indices.resize(verts.size())
		for k in verts.size():
			tri_indices[k] = k

	var num_tris := tri_indices.size() / 3
	if num_tris == 0:
		return

	# 1. Solda vértices na mesma posição 3D (com precisão de 5cm) para calcular normais suavizadas reais
	#    e direção longitudinal real da estrada (via UV V-tangent) mesmo quando o usuário esculpe no Blender!
	var welded_normals: Dictionary = {} # Vector3i -> Vector3
	var welded_fwd: Dictionary = {} # Vector3i -> Vector3
	var vert_keys: Array[Vector3i] = []
	vert_keys.resize(verts.size())
	for idx_v in verts.size():
		var v := verts[idx_v]
		var key := Vector3i(roundi(v.x * 20.0), roundi(v.y * 20.0), roundi(v.z * 20.0))
		vert_keys[idx_v] = key
		if not welded_normals.has(key):
			welded_normals[key] = Vector3.ZERO
			welded_fwd[key] = Vector3.ZERO

	var total_tv_y := 0.0
	for t in num_tris:
		var i0 := tri_indices[t * 3]
		var i1 := tri_indices[t * 3 + 1]
		var i2 := tri_indices[t * 3 + 2]
		var v0 := verts[i0]
		var v1 := verts[i1]
		var v2 := verts[i2]
		var fn := (v2 - v0).cross(v1 - v0)
		if fn.y < 0.0:
			fn = -fn
		# Ignora paredes laterais das muretas (curbs) para não sujar a mureta
		var len_fn := fn.length()
		if len_fn > 0.0001 and (fn.y / len_fn) > 0.72:
			var k0 := vert_keys[i0]
			var k1 := vert_keys[i1]
			var k2 := vert_keys[i2]
			welded_normals[k0] += fn
			welded_normals[k1] += fn
			welded_normals[k2] += fn
			if has_uvs:
				var uv0 := uvs[i0]
				var uv1 := uvs[i1]
				var uv2 := uvs[i2]
				# Ignora muretas laterais (que têm uv.x <= 0.31 em todos os vértices)
				if uv0.x <= 0.31 and uv1.x <= 0.31 and uv2.x <= 0.31:
					continue
				var du1 := uv1.x - uv0.x
				var dv1 := uv1.y - uv0.y
				var du2 := uv2.x - uv0.x
				var dv2 := uv2.y - uv0.y
				var det := du1 * dv2 - du2 * dv1
				if absf(det) > 0.00001:
					var dp1 := v1 - v0
					var dp2 := v2 - v0
					var tv := (dp2 * du1 - dp1 * du2) * (1.0 if det > 0.0 else -1.0)
					total_tv_y += tv.y
					var tv_xz := Vector3(tv.x, 0.0, tv.z)
					if tv_xz.length_squared() > 0.00001:
						var tv_dir := tv_xz.normalized() * len_fn
						welded_fwd[k0] += tv_dir
						welded_fwd[k1] += tv_dir
						welded_fwd[k2] += tv_dir

	# Auto-orienta o sinal do eixo V para apontar sempre no sentido da descida geral da pista (do topo p/ chegada)
	var uv_fwd_sign := 1.0 if total_tv_y <= 0.0 else -1.0

	# 2. Para cada grupo de vértices soldados, calcula a cor e transparência baseadas no declive/aclive real
	var welded_colors: Dictionary = {} # Vector3i -> Color
	var welded_unit_n: Dictionary = {} # Vector3i -> Vector3
	for key: Vector3i in welded_normals:
		var n_sum: Vector3 = welded_normals[key]
		if n_sum.length_squared() < 0.0001:
			welded_colors[key] = Color(0.5, 0.5, 0.5, 0.0)
			welded_unit_n[key] = Vector3.UP
			continue
		var n_unit := n_sum.normalized()
		welded_unit_n[key] = n_unit

		var fwd_sum: Vector3 = (welded_fwd[key] as Vector3) * uv_fwd_sign
		var fwd: Vector3
		var base_drop: float = BASE_SLOPE
		if fwd_sum.length_squared() > 0.0001:
			fwd = fwd_sum.normalized()
		else:
			var world_p := Vector3(float(key.x) * 0.05, float(key.y) * 0.05, float(key.z) * 0.05)
			var track_info := _get_nearest_track_dir_and_slope(world_p)
			fwd = track_info["fwd"]
			base_drop = track_info["base_drop"]

		# Taxa de descida longitudinal na direção da pista (positiva = descendo, negativa = subindo)
		var local_drop: float = n_unit.dot(fwd) / maxf(n_unit.y, 0.35)
		var delta_slope: float = local_drop - base_drop

		var col := Color(0.5, 0.5, 0.5, 0.0)
		if delta_slope > slope_highlight_threshold:
			# Grande Declive -> Azul-Ciano translúcido
			var t_val := clampf((delta_slope - slope_highlight_threshold) / 0.16, 0.0, 1.0)
			col = Color(0.12, 0.90, 1.0, t_val * slope_overlay_opacity)
		elif delta_slope < -slope_highlight_threshold:
			# Grande Aclive / Rampa -> Laranja translúcido
			var t_val := clampf((-delta_slope - slope_highlight_threshold) / 0.16, 0.0, 1.0)
			col = Color(1.0, 0.46, 0.08, t_val * (slope_overlay_opacity + 0.06))
		welded_colors[key] = col

	# 3. Constrói a malha transparente de overlay apenas nos triângulos onde há destaque (alpha > 0.01)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var emitted_tris := 0
	var uv_scale := 0.25

	for t in num_tris:
		var i0 := tri_indices[t * 3]
		var i1 := tri_indices[t * 3 + 1]
		var i2 := tri_indices[t * 3 + 2]
		if has_uvs and uvs[i0].x <= 0.31 and uvs[i1].x <= 0.31 and uvs[i2].x <= 0.31:
			continue
		var k0 := vert_keys[i0]
		var k1 := vert_keys[i1]
		var k2 := vert_keys[i2]
		var c0: Color = welded_colors[k0]
		var c1: Color = welded_colors[k1]
		var c2: Color = welded_colors[k2]
		if c0.a <= 0.01 and c1.a <= 0.01 and c2.a <= 0.01:
			continue

		var v0 := verts[i0] + (welded_unit_n[k0] as Vector3) * 0.03
		var v1 := verts[i1] + (welded_unit_n[k1] as Vector3) * 0.03
		var v2 := verts[i2] + (welded_unit_n[k2] as Vector3) * 0.03

		st.set_color(c0)
		st.set_uv(Vector2(v0.x * uv_scale, v0.z * uv_scale))
		st.set_normal(welded_unit_n[k0])
		st.add_vertex(v0)

		st.set_color(c1)
		st.set_uv(Vector2(v1.x * uv_scale, v1.z * uv_scale))
		st.set_normal(welded_unit_n[k1])
		st.add_vertex(v1)

		st.set_color(c2)
		st.set_uv(Vector2(v2.x * uv_scale, v2.z * uv_scale))
		st.set_normal(welded_unit_n[k2])
		st.add_vertex(v2)
		emitted_tris += 1

	if emitted_tris == 0:
		return

	var overlay_mat := StandardMaterial3D.new()
	overlay_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay_mat.vertex_color_use_as_albedo = true
	overlay_mat.albedo_texture = _get_slope_overlay_texture()
	overlay_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	overlay_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	overlay_mat.render_priority = 1

	var overlay_mi := MeshInstance3D.new()
	overlay_mi.name = "SlopeOverlay"
	overlay_mi.mesh = st.commit()
	overlay_mi.material_override = overlay_mat
	overlay_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	road_mi.add_child(overlay_mi)


## Retorna a direção longitudinal da pista (`fwd`) e a inclinação média esperada (`base_drop`)
## no ponto `world_pos` para calcular se o relevo esculpido é um declive forte ou aclive forte.
func _get_nearest_track_dir_and_slope(world_pos: Vector3) -> Dictionary:
	if samples.size() >= 4:
		var best_d2 := INF
		var best_i := 0
		var step := 6
		for i in range(0, samples.size(), step):
			var p: Vector3 = samples[i]["pos"]
			var dx := world_pos.x - p.x
			var dz := world_pos.z - p.z
			var d2 := dx * dx + dz * dz
			if d2 < best_d2:
				best_d2 = d2
				best_i = i
		for j in range(maxi(0, best_i - step), mini(samples.size(), best_i + step + 1)):
			var p: Vector3 = samples[j]["pos"]
			var dx := world_pos.x - p.x
			var dz := world_pos.z - p.z
			var d2 := dx * dx + dz * dz
			if d2 < best_d2:
				best_d2 = d2
				best_i = j
		return {
			"fwd": samples[best_i]["fwd"],
			"base_drop": BASE_SLOPE,
		}
	var fallback_fwd := (_blender_finish_pos - _blender_spawn_pos)
	fallback_fwd.y = 0.0
	if fallback_fwd.length_squared() > 0.001:
		fallback_fwd = fallback_fwd.normalized()
	else:
		fallback_fwd = _blender_spawn_fwd
	return {
		"fwd": fallback_fwd,
		"base_drop": BASE_SLOPE,
	}


## Encontra a altura exata Y da superfície da malha da estrada (`Pista_Estrada`) nas coordenadas `(wx, wz)`,
## garantindo que o kart sempre dê spawn em cima da pista mesmo antes do primeiro frame da física!
func _sample_road_mesh_height(wx: float, wz: float, fallback_y: float) -> float:
	var best_y := fallback_y
	var best_dist2 := INF
	for mi in _road_meshes_for_spawn:
		if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		var arrays := mi.mesh.surface_get_arrays(0)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var xf := mi.transform
		for v_local in verts:
			var v := xf * v_local
			var dx := v.x - wx
			var dz := v.z - wz
			var d2 := dx * dx + dz * dz
			if d2 < best_dist2:
				best_dist2 = d2
				best_y = v.y
	return best_y


func _ensure_arch_label(arch_node: Node3D, text_str: String) -> void:
	if arch_node.get_node_or_null("ArchLabel3D") != null:
		return
	var lbl := Label3D.new()
	lbl.name = "ArchLabel3D"
	lbl.text = text_str
	lbl.font_size = 42
	lbl.outline_size = 10
	lbl.position = Vector3(0.0, 6.6, 0.35)
	arch_node.add_child(lbl)


# ----------------------------------------------------------------- Ambiente HDRI PS1 & Nós Editáveis

func _apply_editor_perf_settings() -> void:
	if not is_inside_tree():
		return
	var is_ed := Engine.is_editor_hint() and editor_fast_mode
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.shadow_enabled = not is_ed
		sun.light_color = Color(1.0, 0.95, 0.84) if not night_mode else Color(0.55, 0.68, 0.95)
		sun.light_energy = 1.2 if not night_mode else 0.55

	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and we.environment:
		if is_ed:
			we.environment.background_mode = Environment.BG_COLOR
			we.environment.background_color = Color(0.55, 0.72, 0.92)
			we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			we.environment.ambient_light_color = Color(0.85, 0.88, 0.92)
			we.environment.fog_enabled = false
		else:
			var hdri_path := HDRI_NIGHT_PATH if night_mode else HDRI_DAY_PATH
			if ResourceLoader.exists(hdri_path):
				var pano_mat := PanoramaSkyMaterial.new()
				pano_mat.panorama = load(hdri_path)
				pano_mat.filter = false
				var sky := Sky.new()
				sky.sky_material = pano_mat
				we.environment.sky = sky
			we.environment.background_mode = Environment.BG_SKY
			we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
			we.environment.ambient_light_sky_contribution = 0.75
			we.environment.ambient_light_energy = 1.05 if not night_mode else 0.55
			we.environment.fog_enabled = true
			we.environment.fog_light_color = Color(0.58, 0.78, 0.72) if not night_mode else Color(0.12, 0.18, 0.28)
			we.environment.fog_density = 0.0018
			we.environment.fog_sky_affect = 0.35


func _ensure_editor_nodes() -> void:
	if get_node_or_null("WorldEnvironment") == null:
		var env := Environment.new()
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		var we := WorldEnvironment.new()
		we.name = "WorldEnvironment"
		we.environment = env
		add_child(we)
		_set_editable_owner(we)

	if get_node_or_null("Sun") == null:
		var sun := DirectionalLight3D.new()
		sun.name = "Sun"
		sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-32.0), 0.0)
		sun.light_energy = 1.2
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 85.0
		add_child(sun)
		_set_editable_owner(sun)

	var path := get_node_or_null("TrackPath") as Path3D
	if path == null:
		path = Path3D.new()
		path.name = "TrackPath"
		add_child(path)
		_set_editable_owner(path)
	if path.curve == null or path.curve.point_count < 2:
		path.curve = _create_default_curve()
	if not path.curve_changed.is_connected(_queue_rebuild):
		path.curve_changed.connect(_queue_rebuild)

	var zones := get_node_or_null("TrackZones") as Node3D
	if zones == null:
		zones = Node3D.new()
		zones.name = "TrackZones"
		add_child(zones)
		_set_editable_owner(zones)
		_populate_default_zones(zones)

	var scenery := get_node_or_null("Scenery") as Node3D
	if scenery == null:
		scenery = Node3D.new()
		scenery.name = "Scenery"
		add_child(scenery)
		_set_editable_owner(scenery)

	var gen := get_node_or_null("GeneratedTrack") as Node3D
	if gen == null:
		gen = Node3D.new()
		gen.name = "GeneratedTrack"
		add_child(gen)


func _set_editable_owner(node: Node) -> void:
	if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
		node.owner = get_tree().edited_scene_root


func _populate_default_zones(zones_parent: Node3D) -> void:
	var z1: Node3D = TRACK_ZONE_SCRIPT.new()
	z1.name = "DecliveForte_Dir_01"
	z1.position = Vector3(-165.0, -35.0, -18.0)
	z1.set("depth_offset", -2.4)
	z1.set("zone_width", 5.5)
	z1.set("zone_length", 18.0)
	zones_parent.add_child(z1)
	_set_editable_owner(z1)

	var z2: Node3D = TRACK_ZONE_SCRIPT.new()
	z2.name = "LombadaSalto_Esq_01"
	z2.position = Vector3(-95.0, -42.0, -12.0)
	z2.set("depth_offset", 1.9)
	z2.set("zone_width", 5.0)
	z2.set("zone_length", 12.0)
	zones_parent.add_child(z2)
	_set_editable_owner(z2)

	var z3: Node3D = TRACK_ZONE_SCRIPT.new()
	z3.name = "DecliveCurva_Interna_02"
	z3.position = Vector3(390.0, -88.0, 2.0)
	z3.set("depth_offset", -2.8)
	z3.set("zone_width", 6.0)
	z3.set("zone_length", 22.0)
	zones_parent.add_child(z3)
	_set_editable_owner(z3)


func _create_default_curve() -> Curve3D:
	var c := Curve3D.new()
	c.bake_interval = sample_step
	c.up_vector_enabled = true
	var n := CONTROL_POINTS_2D.size()
	var dist := 0.0
	var pts3d: Array[Vector3] = []
	for i in n:
		var p2: Vector2 = CONTROL_POINTS_2D[i] * WORLD_SCALE
		if i > 0:
			var prev2: Vector2 = CONTROL_POINTS_2D[i - 1] * WORLD_SCALE
			dist += p2.distance_to(prev2)
		var y := -dist * BASE_SLOPE
		pts3d.append(Vector3(p2.x, y, p2.y))
	for i in n:
		var prev_p := pts3d[maxi(0, i - 1)]
		var next_p := pts3d[mini(n - 1, i + 1)]
		var tangent := (next_p - prev_p) * 0.28
		c.add_point(pts3d[i], -tangent, tangent)
	return c


func reset_default_curve() -> void:
	_ensure_editor_nodes()
	var path := get_node("TrackPath") as Path3D
	path.curve = _create_default_curve()
	rebuild_track()


# ----------------------------------------------------------------- Reconstrução da Pista e Chão da Selva

func rebuild_track() -> void:
	_ensure_editor_nodes()
	_cache_track_zones()
	_generate_centerline_from_path()

	var gen := get_node("GeneratedTrack") as Node3D
	for child in gen.get_children():
		child.free()

	# Se o modo Blender (.blend) estiver ativo e o arquivo existir, carrega o mapa do Blender!
	if use_blender_map and _load_from_blender_map(gen):
		_using_active_blender_map = true
		return

	_using_active_blender_map = false
	var path_node := get_node_or_null("TrackPath") as Node3D
	if path_node:
		path_node.visible = true
	var zones_node := get_node_or_null("TrackZones") as Node3D
	if zones_node:
		zones_node.visible = true

	_build_track_and_jungle_chunks(gen)
	_build_start_and_finish_banners(gen)
	_update_tropical_forest()


func _cache_track_zones() -> void:
	_zones_cache.clear()
	var zones_node := get_node_or_null("TrackZones")
	if zones_node == null:
		return
	for child in zones_node.get_children():
		if child is Node3D and child.visible:
			var depth := 0.0
			if "depth_offset" in child:
				depth = float(child.get("depth_offset"))
			else:
				depth = child.scale.y
			var radius_xz := Vector2(maxf(absf(child.scale.x) * 8.0, 3.0), maxf(absf(child.scale.z) * 14.0, 4.0))
			if "zone_width" in child and "zone_length" in child:
				radius_xz = Vector2(maxf(float(child.get("zone_width")), 2.0), maxf(float(child.get("zone_length")), 2.0))
			_zones_cache.append({
				"inv_xform": child.global_transform.affine_inverse(),
				"depth": depth,
				"size": radius_xz,
			})


func _effective_step() -> float:
	if Engine.is_editor_hint() and editor_fast_mode:
		return maxf(sample_step, 12.0)
	return sample_step


func _effective_slices() -> int:
	if Engine.is_editor_hint() and editor_fast_mode:
		return 4
	return cross_slices


func _generate_centerline_from_path() -> void:
	var path := get_node("TrackPath") as Path3D
	var curve := path.curve
	var total_len := curve.get_baked_length()
	var step := _effective_step()
	samples.clear()
	if total_len <= 0.1:
		total_length = 0.0
		return
	var count := maxi(2, int(ceil(total_len / step)) + 1)
	for i in count:
		var d := minf(float(i) * step, total_len)
		var xform := curve.sample_baked_with_rotation(d, true, true)
		var wp := path.to_global(xform.origin)
		var d_prev := maxf(0.0, d - step * 0.5)
		var d_next := minf(total_len, d + step * 0.5)
		var prev_p := path.to_global(curve.sample_baked(d_prev, true))
		var next_p := path.to_global(curve.sample_baked(d_next, true))
		var fwd := (next_p - prev_p)
		fwd.y = 0.0
		if fwd.length_squared() < 0.0001:
			fwd = Vector3.FORWARD
		else:
			fwd = fwd.normalized()
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		var up_local := xform.basis.y
		var tilt_angle := asin(clampf(up_local.dot(right), -1.0, 1.0))
		samples.append({
			"pos": wp,
			"fwd": fwd,
			"right": right,
			"tilt": tilt_angle,
			"dist": d,
		})
	total_length = total_len


func _surface_height(d: float, lat: float, base_pos: Vector3, right: Vector3, tilt_angle: float) -> float:
	var base_y := base_pos.y + sin(tilt_angle) * lat
	var env := smoothstep(12.0, 42.0, d) * (1.0 - smoothstep(total_length - 45.0, total_length - 12.0, d))

	var u := clampf(lat / half_width, -1.0, 1.0)
	var center_wave := (sin(d * 0.075) * 1.45 + sin(d * 0.16 + 1.1) * 0.75) * procedural_waves_intensity
	var side_tilt := (sin(d * 0.095 + 0.4) * 1.65 + cos(d * 0.185 - 0.8) * 1.05) * u * lateral_pockets_intensity
	var channel_wave := sin(d * 0.13 + 2.2) * (u * u - 0.45) * 1.55 * lateral_pockets_intensity
	var bump_phase := sin(d * 0.22 + u * 1.7)
	var sharp_crest := pow(maxf(0.0, bump_phase), 3.0) * 1.35 * crest_bumps_intensity

	var y := base_y + (center_wave + side_tilt + channel_wave + sharp_crest) * env

	if not _zones_cache.is_empty():
		var world_xz := Vector3(base_pos.x, base_y, base_pos.z) + right * lat
		for z in _zones_cache:
			var local_p: Vector3 = z["inv_xform"] * world_xz
			var sz: Vector2 = z["size"]
			var nx := local_p.x / sz.x
			var nz := local_p.z / sz.y
			var r2 := nx * nx + nz * nz
			if r2 < 1.0:
				var falloff := (1.0 - r2) * (1.0 - r2)
				y += float(z["depth"]) * falloff
	return y


func _jungle_ground_height(s: Dictionary, side_sign: float, out_dist: float) -> float:
	var d: float = s["dist"]
	var cpos: Vector3 = s["pos"]
	var right: Vector3 = s["right"]
	var tilt_angle: float = s["tilt"]
	var edge_lat := side_sign * half_width
	var edge_y := _surface_height(d, edge_lat, cpos, right, tilt_angle)
	if out_dist <= 0.1:
		return edge_y
	var hill := sin(d * 0.045 + side_sign * 1.3) * 3.8 + cos(d * 0.11 - side_sign * 0.7) * 1.8
	var rise := (out_dist / terrain_skirt_width) * (4.5 + hill) + sin(out_dist * 0.18 + d * 0.06) * 1.1
	return edge_y + rise


func _make_psx_material(tex_path: String, use_vertex_color := true, roughness_val := 0.92) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = use_vertex_color
	mat.roughness = roughness_val
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	if ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path)
	return mat


func _build_track_and_jungle_chunks(parent: Node3D) -> void:
	if samples.size() < 2:
		return
	var road_mat := _make_psx_material(TEX_ROAD_GRAVEL, false, 0.9)
	road_mat.albedo_color = Color(0.88, 0.82, 0.72)
	var jungle_mat := _make_psx_material(TEX_JUNGLE_GRASS, true, 0.96)

	var chunk_size := 120
	var num_samples := samples.size()
	var start_idx := 0
	while start_idx < num_samples - 1:
		var end_idx := mini(start_idx + chunk_size, num_samples - 1)
		_build_single_chunk(parent, start_idx, end_idx, road_mat, jungle_mat, false)
		start_idx = end_idx


func _build_single_chunk(parent: Node3D, i_start: int, i_end: int, road_mat: Material, jungle_mat: Material, for_export := false) -> void:
	var slices := _effective_slices()
	var st_road := SurfaceTool.new()
	st_road.begin(Mesh.PRIMITIVE_TRIANGLES)

	var st_jungle := SurfaceTool.new()
	st_jungle.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rings: Array = []
	for i in range(i_start, i_end + 1):
		var s := samples[i]
		var d: float = s["dist"]
		var cpos: Vector3 = s["pos"]
		var right: Vector3 = s["right"]
		var tilt_angle: float = s["tilt"]
		var ring_pts: Array[Vector3] = []
		for j in range(slices + 1):
			var frac := float(j) / float(slices)
			var lat := lerpf(-half_width, half_width, frac)
			var y := _surface_height(d, lat, cpos, right, tilt_angle)
			ring_pts.append(Vector3(cpos.x, y, cpos.z) + right * lat)
		rings.append(ring_pts)

	var uv_scale_road := 0.16
	var uv_scale_jungle := 0.12
	var skirt_steps := [0.0, 12.0, 28.0, terrain_skirt_width]
	var neutral_road_col := Color(0.88, 0.82, 0.72, 1.0)

	for r in range(rings.size() - 1):
		var i := i_start + r
		var d0: float = samples[i]["dist"]
		var d1: float = samples[i + 1]["dist"]
		var cpos0: Vector3 = samples[i]["pos"]
		var cpos1: Vector3 = samples[i + 1]["pos"]
		var row0: Array[Vector3] = rings[r]
		var row1: Array[Vector3] = rings[r + 1]
		var r0: Vector3 = samples[i]["right"]
		var r1: Vector3 = samples[i + 1]["right"]

		# 1. Superfície da pista com UVs limpos (as cores laranja/azul ficam na camada translúcida dinâmica!)
		for j in range(slices):
			var p00 := row0[j]
			var p01 := row0[j + 1]
			var p10 := row1[j]
			var p11 := row1[j + 1]

			var u0 := float(j) / float(slices) * (half_width * 2.0 * uv_scale_road)
			var u1 := float(j + 1) / float(slices) * (half_width * 2.0 * uv_scale_road)
			var v0 := d0 * uv_scale_road
			var v1 := d1 * uv_scale_road
			_add_quad_uv(st_road, p00, p01, p11, p10, Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1), neutral_road_col)

		# 2. Muretas nas bordas da trilha tropical
		var curb_col := Color(0.58, 0.4, 0.24) if (i / 2) % 2 == 0 else Color(0.42, 0.52, 0.28)
		var cv0 := d0 * uv_scale_road
		var cv1 := d1 * uv_scale_road

		var l_in0 := row0[0]
		var l_in1 := row1[0]
		var l_top0 := l_in0 - r0 * (curb_width * 0.3) + Vector3.UP * curb_height
		var l_top1 := l_in1 - r1 * (curb_width * 0.3) + Vector3.UP * curb_height
		var l_out0 := l_in0 - r0 * curb_width + Vector3.UP * curb_height
		var l_out1 := l_in1 - r1 * curb_width + Vector3.UP * curb_height
		_add_quad_uv(st_road, l_top0, l_in0, l_in1, l_top1, Vector2(0, cv0), Vector2(0.3, cv0), Vector2(0.3, cv1), Vector2(0, cv1), curb_col)
		_add_quad_uv(st_road, l_out0, l_top0, l_top1, l_out1, Vector2(0, cv0), Vector2(0.3, cv0), Vector2(0.3, cv1), Vector2(0, cv1), curb_col.darkened(0.15))

		var r_in0 := row0[slices]
		var r_in1 := row1[slices]
		var r_top0 := r_in0 + r0 * (curb_width * 0.3) + Vector3.UP * curb_height
		var r_top1 := r_in1 + r1 * (curb_width * 0.3) + Vector3.UP * curb_height
		var r_out0 := r_in0 + r0 * curb_width + Vector3.UP * curb_height
		var r_out1 := r_in1 + r1 * curb_width + Vector3.UP * curb_height
		_add_quad_uv(st_road, r_in0, r_top0, r_top1, r_in1, Vector2(0, cv0), Vector2(0.3, cv0), Vector2(0.3, cv1), Vector2(0, cv1), curb_col)
		_add_quad_uv(st_road, r_top0, r_out0, r_out1, r_top1, Vector2(0, cv0), Vector2(0.3, cv0), Vector2(0.3, cv1), Vector2(0, cv1), curb_col.darkened(0.15))

		# 3. Chão da Floresta Tropical margeando os dois lados da descida
		for side: float in [-1.0, 1.0]:
			for s_idx in range(skirt_steps.size() - 1):
				var od_a: float = skirt_steps[s_idx]
				var od_b: float = skirt_steps[s_idx + 1]
				var lat_a := side * (half_width + curb_width + od_a)
				var lat_b := side * (half_width + curb_width + od_b)
				var ya0 := _jungle_ground_height(samples[i], side, od_a)
				var yb0 := _jungle_ground_height(samples[i], side, od_b)
				var ya1 := _jungle_ground_height(samples[i + 1], side, od_a)
				var yb1 := _jungle_ground_height(samples[i + 1], side, od_b)

				var pa0 := Vector3(cpos0.x, ya0, cpos0.z) + r0 * lat_a
				var pb0 := Vector3(cpos0.x, yb0, cpos0.z) + r0 * lat_b
				var pa1 := Vector3(cpos1.x, ya1, cpos1.z) + r1 * lat_a
				var pb1 := Vector3(cpos1.x, yb1, cpos1.z) + r1 * lat_b

				var j_col := Color(0.85, 0.95, 0.8) if s_idx % 2 == 0 else Color(0.72, 0.88, 0.7)
				var ju0 := od_a * uv_scale_jungle
				var ju1 := od_b * uv_scale_jungle
				var jv0 := d0 * uv_scale_jungle
				var jv1 := d1 * uv_scale_jungle
				if side > 0.0:
					_add_quad_uv(st_jungle, pa0, pb0, pb1, pa1, Vector2(ju0, jv0), Vector2(ju1, jv0), Vector2(ju1, jv1), Vector2(ju0, jv1), j_col)
				else:
					_add_quad_uv(st_jungle, pb0, pa0, pa1, pb1, Vector2(ju1, jv0), Vector2(ju0, jv0), Vector2(ju0, jv1), Vector2(ju1, jv1), j_col)

	st_road.set_material(road_mat)
	st_road.generate_normals()
	var road_mesh := st_road.commit()
	var mi_road := MeshInstance3D.new()
	mi_road.name = "Pista_Estrada" if for_export else "RoadChunk_%d" % i_start
	mi_road.mesh = road_mesh
	mi_road.material_override = road_mat
	mi_road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi_road)
	if not for_export and show_dynamic_slope_overlay:
		_build_dynamic_slope_overlay_for_mesh(mi_road)

	st_jungle.set_material(jungle_mat)
	st_jungle.generate_normals()
	var jungle_mesh := st_jungle.commit()
	var mi_jungle := MeshInstance3D.new()
	mi_jungle.name = "Terreno_Selva" if for_export else "JungleChunk_%d" % i_start
	mi_jungle.mesh = jungle_mesh
	mi_jungle.material_override = jungle_mat
	mi_jungle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi_jungle)

	if not Engine.is_editor_hint() and not for_export:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		var shape := road_mesh.create_trimesh_shape()
		shape.backface_collision = true
		cs.shape = shape
		body.add_child(cs)
		parent.add_child(body)


func _add_quad_uv(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uva: Vector2, uvb: Vector2, uvc: Vector2, uvd: Vector2, col: Color) -> void:
	st.set_color(col)
	var verts := [a, c, b, a, d, c]
	var uvs := [uva, uvc, uvb, uva, uvd, uvc]
	for k in 6:
		st.set_uv(uvs[k])
		st.add_vertex(verts[k])


# ----------------------------------------------------------------- Spawns e Progresso

func get_spawn_point(slot: int) -> Dictionary:
	var col := slot % 3
	var row := slot / 3
	var lateral := (col - 1) * 2.8

	if _using_active_blender_map:
		# Posiciona os karts alinhados com o pórtico "Largada" (1.5m atrás da linha do pórtico)
		# e ajusta a altura Y exatamente sobre a superfície esculpida da malha "Pista_Estrada"!
		var p := _blender_spawn_pos + _blender_spawn_right * lateral - _blender_spawn_fwd * (1.5 + float(row) * 3.4)
		var mesh_y := _sample_road_mesh_height(p.x, p.z, _blender_spawn_pos.y)
		p.y = mesh_y + 0.85
		if is_inside_tree() and get_world_3d() and get_world_3d().direct_space_state:
			var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, mesh_y + 20.0, p.z), Vector3(p.x, mesh_y - 25.0, p.z), 1)
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				p.y = (hit["position"] as Vector3).y + 0.85
		var heading_b := atan2(-_blender_spawn_fwd.x, -_blender_spawn_fwd.z)
		return {"pos": p, "heading": heading_b}

	if samples.size() < 6:
		return {"pos": Vector3(0, 2, 0), "heading": 0.0}
	var idx := clampi(4 - row, 1, 6)
	var s := samples[idx]
	var pos_p: Vector3 = s["pos"] + s["right"] * lateral
	pos_p.y = _surface_height(s["dist"], lateral, s["pos"], s["right"], s["tilt"]) + 0.85
	var f: Vector3 = s["fwd"]
	var heading := atan2(-f.x, -f.z)
	return {"pos": pos_p, "heading": heading}


func compute_progress(world_pos: Vector3) -> float:
	if samples.is_empty() or total_length <= 1.0:
		var total_d := _blender_spawn_pos.distance_to(_blender_finish_pos)
		if total_d <= 1.0:
			return 0.0
		var rem_d := world_pos.distance_to(_blender_finish_pos)
		return clampf(1.0 - (rem_d / total_d), 0.0, 1.0)
	var best_d2 := INF
	var best_dist := 0.0
	var step := 4
	var best_i := 0
	for i in range(0, samples.size(), step):
		var d2 := world_pos.distance_squared_to(samples[i]["pos"])
		if d2 < best_d2:
			best_d2 = d2
			best_i = i
	for j in range(maxi(0, best_i - step), mini(samples.size(), best_i + step + 1)):
		var d2 := world_pos.distance_squared_to(samples[j]["pos"])
		if d2 < best_d2:
			best_d2 = d2
			best_dist = samples[j]["dist"]
	return clampf(best_dist / total_length, 0.0, 1.0)


# ----------------------------------------------------------------- Pórticos Retrô de Madeira & Floresta Tropical

func _build_start_and_finish_banners(parent: Node3D, for_export := false) -> void:
	if samples.size() < 12:
		return
	if Engine.is_editor_hint() and editor_fast_mode and not for_export:
		return
	_build_arch(parent, samples[3], Color(0.35, 0.85, 0.42), "LARGADA — SELVA TROPICAL!", "Largada", for_export)
	var finish_sample := samples[samples.size() - 4]
	_build_arch(parent, finish_sample, Color(0.98, 0.8, 0.2), "CHEGADA!", "Chegada", for_export)

	if not Engine.is_editor_hint() and not for_export:
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 2
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(half_width * 2.2, 8.0, 4.0)
		cs.shape = box
		area.add_child(cs)
		var f: Vector3 = finish_sample["fwd"]
		var heading := atan2(-f.x, -f.z)
		area.transform = Transform3D(Basis(Vector3.UP, heading), finish_sample["pos"] + Vector3.UP * 3.0)
		area.body_entered.connect(_on_finish_entered)
		parent.add_child(area)


func _build_arch(parent: Node3D, s: Dictionary, banner_color: Color, label_text: String, node_name := "Arch", for_export := false) -> void:
	var root := Node3D.new()
	root.name = node_name
	var f: Vector3 = s["fwd"]
	var heading := atan2(-f.x, -f.z)
	root.transform = Transform3D(Basis(Vector3.UP, heading), s["pos"])

	var wood_mat := _make_psx_material(TEX_PS1_WOOD, false, 0.85)
	var pillar_mesh := CylinderMesh.new()
	pillar_mesh.top_radius = 0.42
	pillar_mesh.bottom_radius = 0.5
	pillar_mesh.height = 7.2
	pillar_mesh.radial_segments = 6
	pillar_mesh.material = wood_mat

	for side: float in [-1.0, 1.0]:
		var p := MeshInstance3D.new()
		p.name = node_name + ("_PilarEsq" if side < 0.0 else "_PilarDir")
		p.mesh = pillar_mesh
		p.position = Vector3(side * (half_width + 0.5), 3.5, 0.0)
		root.add_child(p)

	var beam_mat := _make_psx_material(TEX_PS1_WOOD, false, 0.8)
	beam_mat.albedo_color = banner_color
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(half_width * 2.2, 1.4, 0.6)
	beam_mesh.material = beam_mat
	var beam := MeshInstance3D.new()
	beam.name = node_name + "_Faixa"
	beam.mesh = beam_mesh
	beam.position = Vector3(0.0, 6.6, 0.0)
	root.add_child(beam)

	if not for_export:
		_ensure_arch_label(root, label_text)
	parent.add_child(root)


func _on_finish_entered(body: Node3D) -> void:
	if body.has_meta("kart"):
		var k: Kart = body.get_meta("kart")
		if k.finished_time <= 0.0 and k.race_time > 10.0:
			k.finished_time = k.race_time


func _extract_retro_mesh(scene_path: String, child_name := "") -> Dictionary:
	var cache_key := scene_path + "::" + child_name
	if _mesh_cache.has(cache_key):
		return (_mesh_cache[cache_key] as Dictionary).duplicate()
	if not ResourceLoader.exists(scene_path):
		return {}
	if not _packed_cache.has(scene_path):
		_packed_cache[scene_path] = load(scene_path)
	var packed := _packed_cache[scene_path] as PackedScene
	if packed == null:
		return {}
	var inst := packed.instantiate()
	var target_mi: MeshInstance3D = null
	if child_name != "":
		target_mi = inst.find_child(child_name + "*", true, false) as MeshInstance3D
	if target_mi == null:
		var all := inst.find_children("*", "MeshInstance3D", true, false)
		if not all.is_empty():
			target_mi = all[0] as MeshInstance3D
	var result := {}
	if target_mi and target_mi.mesh:
		var mesh_copy: Mesh = target_mi.mesh.duplicate()
		for surf_idx in mesh_copy.get_surface_count():
			var mat := target_mi.get_active_material(surf_idx)
			if mat is BaseMaterial3D:
				var m_copy: BaseMaterial3D = mat.duplicate()
				m_copy.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
				m_copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				m_copy.alpha_scissor_threshold = 0.45
				m_copy.cull_mode = BaseMaterial3D.CULL_DISABLED
				mesh_copy.surface_set_material(surf_idx, m_copy)
		result = {
			"mesh": mesh_copy,
			"basis": target_mi.transform.basis,
		}
		_mesh_cache[cache_key] = result
	inst.free()
	return result.duplicate()


func _collect_forest_entries() -> Array[Dictionary]:
	var tree_entries: Array[Dictionary] = []
	var tree_scales := [4.2, 2.6, 3.0, 2.3, 4.5, 2.2]
	var tree_names := ["Floresta_Arvore_1", "Floresta_Arvore_2", "Floresta_Arvore_3", "Floresta_Arvore_4", "Floresta_ArvorePeq", "Floresta_ArvoreSeca"]
	for idx in RETRO_TREE_GLBS.size():
		var data := _extract_retro_mesh(RETRO_TREE_GLBS[idx])
		if not data.is_empty():
			data["export_name"] = tree_names[idx]
			data["scale"] = tree_scales[idx]
			data["transforms"] = []
			tree_entries.append(data)
	for psx_tree in ["PSX_Tree1", "PSX_Tree2", "PSX_Tree4"]:
		var tdata := _extract_retro_mesh(PSX_FOREST_FBX, psx_tree)
		if not tdata.is_empty():
			tdata["export_name"] = "Floresta_" + psx_tree
			tdata["scale"] = 135.0
			tdata["transforms"] = []
			tree_entries.append(tdata)

	var prop_defs := [
		{"scene": PSX_FOREST_FBX, "name": "PSX_Rock", "export_name": "Floresta_Pedras_1", "scale": 135.0},
		{"scene": PSX_FOREST_FBX, "name": "PSX_Treetrunk", "export_name": "Floresta_Troncos", "scale": 140.0},
		{"scene": PSX_FOREST_FBX, "name": "PSX_Reed", "export_name": "Floresta_Juncos", "scale": 160.0},
		{"scene": PSX_FOREST_FBX, "name": "PSX_Grass", "export_name": "Floresta_GramaAlta", "scale": 165.0},
		{"scene": PSX_FOREST_FBX, "name": "PSX_Lavender", "export_name": "Floresta_FloresRoxas", "scale": 140.0},
		{"scene": PSX_FOREST_FBX, "name": "PSX_Dandelion", "export_name": "Floresta_FloresAmarelas", "scale": 150.0},
		{"scene": "res://Assets/scene.gltf", "name": "PS1Bush_5", "export_name": "Floresta_Arbustos", "scale": 1.15},
		{"scene": "res://Assets/scene.gltf", "name": "Rock1_17", "export_name": "Floresta_Pedras_2", "scale": 1.1},
	]
	var prop_entries: Array[Dictionary] = []
	for pdef in prop_defs:
		var pdata := _extract_retro_mesh(pdef["scene"], pdef["name"])
		if not pdata.is_empty():
			pdata["export_name"] = pdef["export_name"]
			pdata["scale"] = pdef["scale"]
			pdata["transforms"] = []
			prop_entries.append(pdata)

	var rng := RandomNumberGenerator.new()
	rng.seed = 641996

	if not tree_entries.is_empty():
		for i in range(4, samples.size() - 4, 2):
			var s := samples[i]
			var cpos: Vector3 = s["pos"]
			var right: Vector3 = s["right"]
			for side: float in [-1.0, 1.0]:
				for layer in 2:
					if layer == 0 and (i % 3 != 0):
						continue
					var out_d := rng.randf_range(3.5, 14.0) if layer == 0 else rng.randf_range(15.0, terrain_skirt_width - 4.0)
					var lat := side * (half_width + curb_width + out_d)
					var y := _jungle_ground_height(s, side, out_d) - 0.35
					var pos := Vector3(cpos.x, y, cpos.z) + right * lat
					var t_idx := rng.randi_range(0, tree_entries.size() - 1)
					if t_idx == 5 and rng.randf() > 0.25:
						t_idx = 0
					var entry := tree_entries[t_idx]
					var sc: float = float(entry["scale"]) * rng.randf_range(0.82, 1.38)
					var yaw := rng.randf() * TAU
					var mesh_basis: Basis = entry["basis"].orthonormalized()
					var final_basis := Basis(Vector3.UP, yaw) * mesh_basis.scaled(Vector3.ONE * sc)
					entry["transforms"].append(Transform3D(final_basis, pos))

	if not prop_entries.is_empty():
		for i in range(3, samples.size() - 3, 2):
			var s := samples[i]
			var cpos: Vector3 = s["pos"]
			var right: Vector3 = s["right"]
			for side: float in [-1.0, 1.0]:
				var out_d := rng.randf_range(1.2, 22.0)
				var lat := side * (half_width + curb_width + out_d)
				var y := _jungle_ground_height(s, side, out_d) - 0.1
				var pos := Vector3(cpos.x, y, cpos.z) + right * lat
				var p_idx := rng.randi_range(0, prop_entries.size() - 1)
				var pentry := prop_entries[p_idx]
				var sc: float = float(pentry["scale"]) * rng.randf_range(0.75, 1.45)
				var yaw := rng.randf() * TAU
				var unit_basis: Basis = pentry["basis"].orthonormalized()
				var final_basis := Basis(Vector3.UP, yaw) * unit_basis.scaled(Vector3.ONE * sc)
				pentry["transforms"].append(Transform3D(final_basis, pos))

	var all_entries: Array[Dictionary] = []
	all_entries.append_array(tree_entries)
	all_entries.append_array(prop_entries)
	return all_entries


func _update_tropical_forest() -> void:
	var gen := get_node_or_null("GeneratedTrack")
	if gen == null:
		return
	var old := gen.get_node_or_null("TropicalForest")
	if old:
		old.free()
	if Engine.is_editor_hint() and not show_trees_in_editor:
		return
	if samples.size() < 10:
		return

	var forest_root := Node3D.new()
	forest_root.name = "TropicalForest"
	gen.add_child(forest_root)

	for entry in _collect_forest_entries():
		var xforms: Array = entry["transforms"]
		if xforms.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = entry["mesh"]
		mm.instance_count = xforms.size()
		for k in xforms.size():
			mm.set_instance_transform(k, xforms[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		forest_root.add_child(mmi)


func _build_combined_forest_for_export(parent: Node3D) -> void:
	for entry in _collect_forest_entries():
		var xforms: Array = entry["transforms"]
		var src_mesh := entry["mesh"] as Mesh
		if xforms.is_empty() or src_mesh == null:
			continue
		var combined := ArrayMesh.new()
		for surf_idx in src_mesh.get_surface_count():
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var mat := src_mesh.surface_get_material(surf_idx)
			if mat:
				st.set_material(mat)
			for xf: Transform3D in xforms:
				st.append_from(src_mesh, surf_idx, xf)
			st.commit(combined)
		var mi := MeshInstance3D.new()
		mi.name = str(entry.get("export_name", "Floresta_Item"))
		mi.mesh = combined
		parent.add_child(mi)
