import bpy
import hashlib
import os
import struct
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT_DIR = os.path.join(ROOT, "assets", "basket")
DIAG_DIR = os.path.join(OUT_DIR, "top_band_diagnostics")
BLEND_PATH = os.path.join(OUT_DIR, "LowWideWovenBasket.blend")
FBX_PATH = os.path.join(OUT_DIR, "LowWideWovenBasket_Roblox.fbx")
GLB_PATH = os.path.join(OUT_DIR, "LowWideWovenBasket.glb")
PREVIEW_PATH = os.path.join(OUT_DIR, "LowWideWovenBasket_preview.png")
AFTER_PATH = os.path.join(DIAG_DIR, "06_after_exact_fix.png")


def geometry_fingerprint(objects):
    digest = hashlib.sha256()
    for obj in sorted(objects, key=lambda item: item.name):
        digest.update(obj.name.encode("utf-8"))
        digest.update(struct.pack("<16f", *[value for row in obj.matrix_world for value in row]))
        digest.update(struct.pack("<II", len(obj.data.vertices), len(obj.data.polygons)))
        for vertex in obj.data.vertices:
            digest.update(struct.pack("<3f", *vertex.co))
    return digest.hexdigest()


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
geometry_before = geometry_fingerprint(mesh_objects)

core = bpy.data.objects.get("ContinuousSoftTopRim")
front_top = bpy.data.objects.get("FrontBackHorizontalRibbon_-1_7")
if core is None or front_top is None or not front_top.data.materials:
    raise RuntimeError("Required rim core or upper wall ribbon is missing")

# The diagnostic isolation proved that this continuous lower face group—not a
# wall ribbon, panel, wrap strand, or global light—creates the chocolate band.
z_values = [(core.matrix_world @ vertex.co).z for vertex in core.data.vertices]
bottom, top = min(z_values), max(z_values)
limit = bottom + (top - bottom) * 0.34
normal_matrix = core.matrix_world.to_3x3()

source = front_top.data.materials[0]
matched = source.copy()
matched.name = "Upper Wall Wicker - Matched Rim Underside"
matched.diffuse_color = source.diffuse_color[:]

nodes = matched.node_tree.nodes
links = matched.node_tree.links
bsdf = next((node for node in nodes if node.type == "BSDF_PRINCIPLED"), None)
ramp = next((node for node in nodes if node.type == "VALTORGB"), None)
bump = next((node for node in nodes if node.type == "BUMP"), None)
if bsdf:
    bsdf.inputs["Roughness"].default_value = 0.95
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.12
    # Preserve the exact upper-wall colour source while preventing downward
    # normals and close overlap from multiplying into a near-black stripe.
    if ramp and "Emission Color" in bsdf.inputs:
        links.new(ramp.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.00
if bump:
    bump.inputs["Strength"].default_value *= 0.55

slot = len(core.data.materials)
core.data.materials.append(matched)
reassigned = 0
for polygon in core.data.polygons:
    centre_z = sum(
        (core.matrix_world @ core.data.vertices[index].co).z
        for index in polygon.vertices
    ) / len(polygon.vertices)
    normal_z = (normal_matrix @ polygon.normal).normalized().z
    if centre_z <= limit and normal_z < 0.28:
        polygon.material_index = slot
        polygon.use_smooth = True
        reassigned += 1

bpy.context.view_layer.update()
geometry_after = geometry_fingerprint(mesh_objects)
if geometry_before != geometry_after:
    raise RuntimeError("Geometry changed during exact face-group material fix")

scene = bpy.context.scene
scene.render.filepath = PREVIEW_PATH
bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)

# Export the unchanged shape with the corrected face assignment.
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

# Render the exact same diagnostic front camera for an apples-to-apples check.
camera = scene.camera
camera.location = (0.0, -5.50, 0.96)
camera.data.lens = 60
look_at(camera, (0.0, -1.00, 0.755))
scene.render.resolution_x = 1200
scene.render.resolution_y = 420
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = AFTER_PATH
bpy.ops.render.render(write_still=True)

print("Exact stripe source: ContinuousSoftTopRim lower/downward-facing polygons")
print(f"Core underside faces reassigned: {reassigned}")
print(f"New material: {matched.name}; source material: {source.name}")
print(f"Geometry fingerprint unchanged: {geometry_after}")
print(f"Before render: {os.path.join(DIAG_DIR, '00_baseline.png')}")
print(f"After render: {AFTER_PATH}")
