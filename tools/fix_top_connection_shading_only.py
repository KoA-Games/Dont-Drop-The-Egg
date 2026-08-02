import bpy
import hashlib
import os
import struct
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT_DIR = os.path.join(ROOT, "assets", "basket")
BLEND_PATH = os.path.join(OUT_DIR, "LowWideWovenBasket.blend")
FBX_PATH = os.path.join(OUT_DIR, "LowWideWovenBasket_Roblox.fbx")
GLB_PATH = os.path.join(OUT_DIR, "LowWideWovenBasket.glb")
PREVIEW_PATH = os.path.join(OUT_DIR, "LowWideWovenBasket_preview.png")


def geometry_fingerprint(objects):
    digest = hashlib.sha256()
    for obj in sorted(objects, key=lambda item: item.name):
        digest.update(obj.name.encode("utf-8"))
        digest.update(struct.pack("<16f", *[value for row in obj.matrix_world for value in row]))
        digest.update(struct.pack("<II", len(obj.data.vertices), len(obj.data.polygons)))
        for vertex in obj.data.vertices:
            digest.update(struct.pack("<3f", *vertex.co))
    return digest.hexdigest()


def world_z_bounds(objects):
    points = [
        obj.matrix_world @ vertex.co
        for obj in objects for vertex in obj.data.vertices
    ]
    return min(point.z for point in points), max(point.z for point in points)


def tune_copied_wicker(source, name, lift, roughness, bump_factor, emission=0.0):
    material = source.copy()
    material.name = name
    material.diffuse_color = (
        min(1.0, source.diffuse_color[0] * lift[0] + lift[3]),
        min(1.0, source.diffuse_color[1] * lift[1] + lift[4]),
        min(1.0, source.diffuse_color[2] * lift[2] + lift[5]),
        1.0,
    )
    nodes = material.node_tree.nodes
    bsdf = next((node for node in nodes if node.type == "BSDF_PRINCIPLED"), None)
    ramp = next((node for node in nodes if node.type == "VALTORGB"), None)
    bump = next((node for node in nodes if node.type == "BUMP"), None)
    if bsdf:
        bsdf.inputs["Roughness"].default_value = roughness
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.20
        if emission and ramp and "Emission Color" in bsdf.inputs:
            material.node_tree.links.new(ramp.outputs["Color"], bsdf.inputs["Emission Color"])
            bsdf.inputs["Emission Strength"].default_value = emission
    if ramp:
        for element in ramp.color_ramp.elements:
            color = element.color
            element.color = (
                min(1.0, color[0] * lift[0] + lift[3]),
                min(1.0, color[1] * lift[1] + lift[4]),
                min(1.0, color[2] * lift[2] + lift[5]),
                color[3],
            )
    if bump:
        bump.inputs["Strength"].default_value *= bump_factor
    return material


mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
geometry_before = geometry_fingerprint(mesh_objects)

rim_objects = [obj for obj in mesh_objects if "Rim" in obj.name]
if len(rim_objects) != 3:
    raise RuntimeError("Expected exactly three top-rim mesh objects")

rim_bottom, rim_top = world_z_bounds(rim_objects)
transition_limit = rim_bottom + (rim_top - rim_bottom) * 0.34

# A dedicated underside material keeps the contact area in the same wicker
# family while gently lifting the near-black occlusion.  No geometry moves.
core_material = bpy.data.materials.get("Thick Soft Rim")
if core_material is None:
    raise RuntimeError("Top rim material is missing")
underside_material = tune_copied_wicker(
    core_material,
    "Rim Underside Natural Wicker Transition",
    lift=(1.24, 1.30, 1.22, 0.018, 0.014, 0.003),
    roughness=0.94,
    bump_factor=0.72,
    emission=0.10,
)

underside_faces = 0
for obj in rim_objects:
    slot_index = len(obj.data.materials)
    obj.data.materials.append(underside_material)
    normal_matrix = obj.matrix_world.to_3x3()
    for polygon in obj.data.polygons:
        centre_z = sum(
            (obj.matrix_world @ obj.data.vertices[index].co).z
            for index in polygon.vertices
        ) / len(polygon.vertices)
        normal_z = (normal_matrix @ polygon.normal).normalized().z
        if centre_z <= transition_limit and normal_z < 0.28:
            polygon.material_index = slot_index
            polygon.use_smooth = True
            underside_faces += 1

# Give only the highest wall course a closer, calmer wicker tone.  Copies are
# used so no lower wall course or shared body material changes.
top_ribbons = [
    obj for obj in mesh_objects
    if "HorizontalRibbon" in obj.name
    and obj.name.endswith("_7")
    and "Bottom" not in obj.name
]
material_copies = {}
for obj in top_ribbons:
    if not obj.data.materials:
        continue
    source = obj.data.materials[0]
    if source not in material_copies:
        material_copies[source] = tune_copied_wicker(
            source,
            f"{source.name} - Natural Top Transition",
            lift=(1.07, 1.12, 1.08, 0.008, 0.007, 0.0015),
            roughness=0.90,
            bump_factor=0.82,
        )
    obj.data.materials[0] = material_copies[source]
    for polygon in obj.data.polygons:
        polygon.use_smooth = True

bpy.context.view_layer.update()
geometry_after = geometry_fingerprint(mesh_objects)
if geometry_before != geometry_after:
    raise RuntimeError("Mesh geometry changed during shading-only refinement")

scene = bpy.context.scene
scene.render.filepath = PREVIEW_PATH
bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)

visual_objects = [
    obj for obj in scene.objects
    if obj.type == "MESH" and obj.get("CollisionIntent") == "VisualOnly"
]
bpy.ops.object.select_all(action="DESELECT")
for obj in visual_objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = visual_objects[0]
bpy.ops.object.duplicate()
duplicates = list(bpy.context.selected_objects)
bpy.context.view_layer.objects.active = duplicates[0]
bpy.ops.object.join()
export_mesh = bpy.context.object
export_mesh.name = "LowWideWovenBasket_Export"
bpy.ops.export_scene.fbx(
    filepath=FBX_PATH, use_selection=True, apply_unit_scale=True,
    apply_scale_options="FBX_SCALE_UNITS", axis_forward="-Z", axis_up="Y",
    use_mesh_modifiers=True, mesh_smooth_type="FACE", add_leaf_bones=False,
    bake_anim=False)
bpy.ops.export_scene.gltf(
    filepath=GLB_PATH, export_format="GLB", use_selection=True,
    export_apply=True, export_yup=True)
bpy.data.objects.remove(export_mesh, do_unlink=True)
bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)

print(f"Geometry fingerprint unchanged: {geometry_after}")
print(f"Rim underside transition faces assigned: {underside_faces}")
print(f"Top wall ribbons material-matched: {len(top_ribbons)}")
print("Rim size, position, silhouette, and all weave geometry preserved")
