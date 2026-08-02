import bpy
import hashlib
import math
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
BEFORE_PATH = os.path.join(DIAG_DIR, "08_before_underside_geometry.png")
AFTER_PATH = os.path.join(DIAG_DIR, "09_after_underside_geometry.png")
PATH_SAMPLES = 160


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def geometry_fingerprint(objects):
    digest = hashlib.sha256()
    for obj in sorted(objects, key=lambda item: item.name):
        digest.update(obj.name.encode("utf-8"))
        digest.update(struct.pack("<16f", *[value for row in obj.matrix_world for value in row]))
        digest.update(struct.pack("<II", len(obj.data.vertices), len(obj.data.polygons)))
        for vertex in obj.data.vertices:
            digest.update(struct.pack("<3f", *vertex.co))
    return digest.hexdigest()


def exact_bounds(objects):
    points = [
        obj.matrix_world @ vertex.co
        for obj in objects for vertex in obj.data.vertices
    ]
    return (
        min(point.x for point in points), max(point.x for point in points),
        min(point.y for point in points), max(point.y for point in points),
        min(point.z for point in points), max(point.z for point in points),
    )


def render_front(scene, path):
    camera = scene.camera
    camera.location = (0.0, -5.50, 0.96)
    camera.data.lens = 60
    look_at(camera, (0.0, -1.00, 0.755))
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 420
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


scene = bpy.context.scene
os.makedirs(DIAG_DIR, exist_ok=True)
camera = scene.camera
camera_location = camera.location.copy()
camera_rotation = camera.rotation_euler.copy()
camera_lens = camera.data.lens
render_state = (
    scene.render.resolution_x,
    scene.render.resolution_y,
    scene.render.resolution_percentage,
    scene.render.filepath,
)
render_front(scene, BEFORE_PATH)

mesh_objects = [obj for obj in scene.objects if obj.type == "MESH"]
core = bpy.data.objects.get("ContinuousSoftTopRim")
twists = [
    bpy.data.objects.get("RimDiagonalTwist_1"),
    bpy.data.objects.get("RimDiagonalTwist_2"),
]
if core is None or any(obj is None for obj in twists):
    raise RuntimeError("Expected rim core and two wrap meshes")
if len(core.data.vertices) % PATH_SAMPLES:
    raise RuntimeError("Unexpected core rim topology")

body_objects = [obj for obj in mesh_objects if obj not in [core, *twists]]
body_before = geometry_fingerprint(body_objects)
rim_before = exact_bounds([core, *twists])
core_before = exact_bounds([core])

ring_size = len(core.data.vertices) // PATH_SAMPLES
if ring_size != 8:
    raise RuntimeError(f"Expected eight vertices per core ring, found {ring_size}")

inverse = core.matrix_world.inverted()
changed_vertices = 0
for ring in range(PATH_SAMPLES):
    start = ring * ring_size
    points = [
        core.matrix_world @ core.data.vertices[start + index].co
        for index in range(ring_size)
    ]
    centre = sum(points, Vector()) / ring_size
    # Tiny, non-repeating height variation removes the ruler-straight lower
    # seam while remaining far below silhouette/gameplay significance.
    variation = 0.0008 * math.sin(ring * 0.71) + 0.0004 * math.sin(ring * 1.93)
    for cross_index, rise in ((4, 0.012), (5, 0.018), (6, 0.012)):
        vertex = core.data.vertices[start + cross_index]
        world = core.matrix_world @ vertex.co
        radial = Vector((world.x - centre.x, world.y - centre.y, 0.0))
        # Taper only the hidden lower quadrant toward the rim centreline.
        world.x = centre.x + radial.x * 0.88
        world.y = centre.y + radial.y * 0.88
        world.z += rise + variation
        vertex.co = inverse @ world
        changed_vertices += 1

core.data.update()
bpy.context.view_layer.update()

body_after = geometry_fingerprint(body_objects)
if body_before != body_after:
    raise RuntimeError("A body or wall mesh changed during rim underside refinement")

rim_after = exact_bounds([core, *twists])
core_after = exact_bounds([core])

# The two wrapped strands retain the authored overall rim thickness, and the
# untouched outer-mid/top core vertices retain the external silhouette.
for before, after, label in zip(rim_before[:4], rim_after[:4], ("min X", "max X", "min Y", "max Y")):
    if abs(before - after) > 1e-6:
        raise RuntimeError(f"Overall rim silhouette changed at {label}")

render_front(scene, AFTER_PATH)
camera.location = camera_location
camera.rotation_euler = camera_rotation
camera.data.lens = camera_lens
scene.render.resolution_x = render_state[0]
scene.render.resolution_y = render_state[1]
scene.render.resolution_percentage = render_state[2]
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

print("Changed geometry: ContinuousSoftTopRim cross-section vertices 4, 5, and 6 only")
print(f"Changed core vertices: {changed_vertices}")
print(f"Body geometry fingerprint unchanged: {body_after}")
print(f"Overall rim bounds before: {rim_before}")
print(f"Overall rim bounds after:  {rim_after}")
print(f"Core bottom before: {core_before[4]:.6f}; after: {core_after[4]:.6f}")
print(f"Before front render: {BEFORE_PATH}")
print(f"After front render: {AFTER_PATH}")
