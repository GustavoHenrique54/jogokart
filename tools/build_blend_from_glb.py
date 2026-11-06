import bpy
import sys
import os
from mathutils import Vector, Euler, Quaternion

argv = sys.argv
if "--" in argv:
    args = argv[argv.index("--") + 1:]
else:
    args = []

if len(args) < 2:
    print("Uso: blender -b -P build_blend_from_glb.py -- <input.glb> <output.blend>")
    sys.exit(1)

glb_path = os.path.abspath(args[0])
blend_path = os.path.abspath(args[1])

# 1. Remove objetos iniciais padrão (Cube, Camera, Light) mantendo a interface completa do Blender
for obj in list(bpy.data.objects):
    bpy.data.objects.remove(obj, do_unlink=True)
for mesh in list(bpy.data.meshes):
    bpy.data.meshes.remove(mesh)

# 2. Importa o arquivo GLB gerado pelo Godot com a pista contínua, terreno, largada/chegada e floresta
bpy.ops.import_scene.gltf(filepath=glb_path)

# 3. Cria coleções organizadas no Outliner do Blender
col_track = bpy.data.collections.new("1_Pista_e_Terreno")
col_markers = bpy.data.collections.new("2_Largada_e_Chegada")
col_forest = bpy.data.collections.new("3_Floresta_Vegetacao")
bpy.context.scene.collection.children.link(col_track)
bpy.context.scene.collection.children.link(col_markers)
bpy.context.scene.collection.children.link(col_forest)

def move_to_collection(obj, target_col):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    if obj.name not in target_col.objects:
        target_col.objects.link(obj)

# Desparenteia os filhos diretos do nó raiz de exportação mantendo a matriz global
for obj in list(bpy.data.objects):
    if obj.parent is not None and obj.parent.name in ("GeneratedExport", "RootNode", "TropicalForest"):
        mat = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = mat

for obj in list(bpy.data.objects):
    if obj.type == 'EMPTY' and obj.name in ("GeneratedExport", "RootNode", "TropicalForest") and len(obj.children) == 0:
        bpy.data.objects.remove(obj, do_unlink=True)

# Organiza objetos nas coleções
for obj in list(bpy.data.objects):
    if obj.parent is None:
        nm = obj.name.lower()
        if "pista" in nm or "terreno" in nm:
            move_to_collection(obj, col_track)
        elif "largada" in nm or "chegada" in nm or "spawn" in nm or "finish" in nm:
            move_to_collection(obj, col_markers)
            for ch in obj.children_recursive:
                move_to_collection(ch, col_markers)
        else:
            move_to_collection(obj, col_forest)

# 4. Ajusta os materiais no Blender:
#    - Filtro 'Closest' (Nearest Neighbor PS1/N64)
#    - Garante que a textura Base Color fique conectada diretamente ao Principled BSDF (para exportação glTF perfeita)
for mat in bpy.data.materials:
    mat.use_backface_culling = False
    if mat.use_nodes and mat.node_tree:
        for node in mat.node_tree.nodes:
            if node.type == 'TEX_IMAGE':
                node.interpolation = 'Closest'

# 5. Configura todas as janelas 3D (VIEW_3D) do arquivo .blend para:
#    - Clip End = 15000m (para enxergar toda a descida de 4.2 km sem cortar!)
#    - Shading com Textura visível de imediato
#    - Câmera posicionada na Largada da pista
for window in bpy.context.window_manager.windows:
    for area in window.screen.areas:
        if area.type == 'VIEW_3D':
            for space in area.spaces:
                if space.type == 'VIEW_3D':
                    space.clip_start = 0.5
                    space.clip_end = 15000.0
                    space.shading.type = 'SOLID'
                    space.shading.color_type = 'TEXTURE'
                    if space.region_3d:
                        # Posição da largada no espaço do Blender: X ~ -580, Y ~ 0, Z ~ 0
                        space.region_3d.view_location = Vector((-480.0, 10.0, -5.0))
                        space.region_3d.view_distance = 140.0
                        space.region_3d.view_rotation = Euler((1.1, 0.0, -1.2), 'XYZ').to_quaternion()

# Seleciona a Pista_Estrada por padrão e garante que sua malha no Blender não tenha Vertex Colors fixos
bpy.ops.object.select_all(action='DESELECT')
road_obj = bpy.data.objects.get("Pista_Estrada")
if road_obj:
    if road_obj.data and hasattr(road_obj.data, "color_attributes"):
        while len(road_obj.data.color_attributes) > 0:
            road_obj.data.color_attributes.remove(road_obj.data.color_attributes[0])
    for mat in road_obj.data.materials:
        if mat and mat.use_nodes and mat.node_tree:
            bsdf = next((n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
            tex = next((n for n in mat.node_tree.nodes if n.type == 'TEX_IMAGE'), None)
            if bsdf and tex:
                mat.node_tree.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    road_obj.select_set(True)
    bpy.context.view_layer.objects.active = road_obj

# 6. Salva o arquivo .blend pronto para editar!
os.makedirs(os.path.dirname(blend_path), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=blend_path)
print(f"[Blender] Pista salva com sucesso em: {blend_path}")
