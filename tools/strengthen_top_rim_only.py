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
PATH_SAMPLES = 160


def world_bounds(obj):
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return (
        min(p.x for p in points), max(p.x for p in points),
        min(p.y for p in points), max(p.y for p in points),
        min(p.z for p in points), max(p.z for p in points),
    )


def exact_half_extents(objects):
    points = [
        obj.matrix_world @ vertex.co
        for obj in objects for vertex in obj.data.vertices
    ]
    return max(abs(p.x) for p in points), max(abs(p.y) for p in points)


def body_fingerprint(objects):
    digest = hashlib.sha256()
    for obj in sorted(objects, key=lambda item: item.name):
        digest.update(obj.name.encode("utf-8"))
        digest.update(struct.pack("<16f", *[value for row in obj.matrix_world for value in row]))
        digest.update(struct.pack("<II", len(obj.data.vertices), len(obj.data.polygons)))
        for vertex in obj.data.vertices:
            digest.update(struct.pack("<3f", *vertex.co))
    return digest.hexdigest()


def ring_size(obj):
    if len(obj.data.vertices) % PATH_SAMPLES:
        raise RuntimeError(f"Unexpected rim topology on {obj.name}")
    return len(obj.data.vertices) // PATH_SAMPLES


def ring_centres(obj):
    size = ring_size(obj)
    centres = []
    for ring in range(PATH_SAMPLES):
        start = ring * size
        points = [
            obj.matrix_world @ obj.data.vertices[index].co
            for index in range(start, start + size)
        ]
        centres.append(sum(points, Vector()) / len(points))
    return centres


rim_objects = [
    obj for obj in bpy.context.scene.objects
    if obj.type == "MESH" and "Rim" in obj.name
]
core = bpy.data.objects.get("ContinuousSoftTopRim")
twists = [obj for obj in rim_objects if obj.name.startswith("RimDiagonalTwist_")]
if core is None or core not in rim_objects or len(twists) != 2:
    raise RuntimeError("Expected one core rim and two wrapped rim strands")

body_objects = [
    obj for obj in bpy.context.scene.objects
    if obj.type == "MESH" and obj not in rim_objects
]
body_before = body_fingerprint(body_objects)

old_bounds = [world_bounds(obj) for obj in rim_objects]
old_bottom = min(bounds[4] for bounds in old_bounds)
old_top = max(bounds[5] for bounds in old_bounds)
old_x, old_y = exact_half_extents(rim_objects)

# Reference target: approximately 25-40% more vertical presence than the thin
# rim, but still a flattened band rather than a circular tube.
target_height = 0.091
z_factor = target_height / (old_top - old_bottom)
target_x = old_x + 0.025
target_y = old_y + 0.025

# Increase horizontal/radial thickness more than the vertical profile.  The
# raised wrapping strands grow slightly less than the core and therefore stay
# visually integrated instead of becoming separate cords.
core_centres = ring_centres(core)
radial_factors = {core: 1.22, twists[0]: 1.18, twists[1]: 1.18}
for obj in rim_objects:
    size = ring_size(obj)
    factor = radial_factors[obj]
    inverse = obj.matrix_world.inverted()
    for index, vertex in enumerate(obj.data.vertices):
        world = obj.matrix_world @ vertex.co
        base = core_centres[index // size]
        world.x = base.x + (world.x - base.x) * factor
        world.y = base.y + (world.y - base.y) * factor
        vertex.co = inverse @ world
    obj.data.update()

# Expand the rounded-rectangle centreline just enough to achieve the requested
# overhang after the thicker cross-section has been formed.  Expanding from the
# origin widens both the outer edge and usable opening.
intermediate_x, intermediate_y = exact_half_extents(rim_objects)
x_factor = target_x / intermediate_x
y_factor = target_y / intermediate_y
for obj in rim_objects:
    inverse = obj.matrix_world.inverted()
    for vertex in obj.data.vertices:
        world = obj.matrix_world @ vertex.co
        world.x *= x_factor
        world.y *= y_factor
        world.z = old_bottom + (world.z - old_bottom) * z_factor
        vertex.co = inverse @ world
    obj.data.update()

bpy.context.view_layer.update()
body_after = body_fingerprint(body_objects)
if body_before != body_after:
    raise RuntimeError("A non-rim basket mesh changed during rim strengthening")

new_bounds = [world_bounds(obj) for obj in rim_objects]
new_bottom = min(bounds[4] for bounds in new_bounds)
new_top = max(bounds[5] for bounds in new_bounds)
new_x, new_y = exact_half_extents(rim_objects)

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

print(f"Rim objects strengthened: {[obj.name for obj in rim_objects]}")
print(f"Body mesh fingerprint unchanged: {body_after}")
print(f"Rim half-extents before: X {old_x:.5f}, Y {old_y:.5f}")
print(f"Rim half-extents after:  X {new_x:.5f}, Y {new_y:.5f}")
print(f"Rim height before: {old_top - old_bottom:.5f}")
print(f"Rim height after:  {new_top - new_bottom:.5f}")
print(f"Rim bottom attachment preserved at: {new_bottom:.5f}")
print("Core radial thickness factor: 1.22; wrapped-strand factor: 1.18")
