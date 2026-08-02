import bpy
import os
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT_DIR = os.path.join(ROOT, "assets", "basket")
BLEND_PATH = os.path.join(OUT_DIR, "LowWideWovenBasket.blend")
FBX_PATH = os.path.join(OUT_DIR, "LowWideWovenBasket_Roblox.fbx")
GLB_PATH = os.path.join(OUT_DIR, "LowWideWovenBasket.glb")
PREVIEW_PATH = os.path.join(OUT_DIR, "LowWideWovenBasket_preview.png")


def world_bounds(obj):
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return (
        min(p.x for p in points), max(p.x for p in points),
        min(p.y for p in points), max(p.y for p in points),
        min(p.z for p in points), max(p.z for p in points),
    )


def object_signature(obj):
    bounds = world_bounds(obj)
    return tuple(round(value, 8) for value in (
        *obj.location, *obj.rotation_euler, *obj.scale, *bounds))


rim_objects = [
    obj for obj in bpy.context.scene.objects
    if obj.type == "MESH" and "Rim" in obj.name
]
if not rim_objects:
    raise RuntimeError("No rim mesh objects found")

body_objects = [
    obj for obj in bpy.context.scene.objects
    if obj.type == "MESH" and obj not in rim_objects
]
body_before = {obj.name: object_signature(obj) for obj in body_objects}

rim_bounds = [world_bounds(obj) for obj in rim_objects]
old_bottom = min(bounds[4] for bounds in rim_bounds)
old_top = max(bounds[5] for bounds in rim_bounds)
old_center_z = (old_bottom + old_top) * 0.5

wall_candidates = [
    obj for obj in body_objects
    if "HorizontalRibbon" in obj.name
    and "Bottom" not in obj.name
    and "Inner" not in obj.name
]
wall_top = max(world_bounds(obj)[5] for obj in wall_candidates)

# Flatten only the braided rim cross-section and seat it into the upper wall.
# The body dimensions and every body vertex remain untouched.
target_height = 0.074
vertical_factor = target_height / (old_top - old_bottom)
target_bottom = wall_top - 0.020
target_half_height = target_height * 0.5
target_center_z = target_bottom + target_half_height
radial_thickness_factor = 0.88

# Curve conversion preserves one bevel ring per path sample.  Use the core
# ring centres as the perimeter centreline, then tighten the core, braid path,
# and braid bevels toward that line.  This reduces the puffy tube diameter
# without changing the continuous rounded-rectangle path or its corner flow.
path_samples = 160
core = bpy.data.objects.get("ContinuousSoftTopRim")
if core is None or core not in rim_objects:
    raise RuntimeError("ContinuousSoftTopRim is missing")


def ring_size(obj):
    if len(obj.data.vertices) % path_samples:
        raise RuntimeError(f"Unexpected rim topology on {obj.name}")
    return len(obj.data.vertices) // path_samples


def ring_centres(obj):
    size = ring_size(obj)
    centres = []
    for ring in range(path_samples):
        start = ring * size
        points = [
            obj.matrix_world @ obj.data.vertices[index].co
            for index in range(start, start + size)
        ]
        centres.append(sum(points, Vector()) / len(points))
    return centres


core_centres = ring_centres(core)
interim = {}
vertex_base_centres = {}
for obj in rim_objects:
    size = ring_size(obj)
    positions = []
    bases = []
    for index, vertex in enumerate(obj.data.vertices):
        world = obj.matrix_world @ vertex.co
        base = core_centres[index // size]
        positions.append(Vector((
            base.x + (world.x - base.x) * radial_thickness_factor,
            base.y + (world.y - base.y) * radial_thickness_factor,
            target_center_z + (world.z - old_center_z) * vertical_factor,
        )))
        bases.append(base)
    interim[obj] = positions
    vertex_base_centres[obj] = bases

# Align the tightened rim's outer edge with the existing top wall edge.  This
# closes the apparent radial gap while staying inside the unchanged basket
# silhouette established by the corner supports.
target_outer_x = max(max(abs(b[0]), abs(b[1])) for b in map(world_bounds, wall_candidates))
target_outer_y = max(max(abs(b[2]), abs(b[3])) for b in map(world_bounds, wall_candidates))


def centreline_scale(axis, target):
    best_value = -1.0
    best_base = 0.0
    for obj, positions in interim.items():
        for position, base in zip(positions, vertex_base_centres[obj]):
            value = abs(position[axis])
            if value > best_value:
                best_value = value
                best_base = abs(base[axis])
    if best_base < 1e-6:
        return 1.0
    return 1.0 + (target - best_value) / best_base


x_centreline_factor = centreline_scale(0, target_outer_x)
y_centreline_factor = centreline_scale(1, target_outer_y)

for obj in rim_objects:
    inverse = obj.matrix_world.inverted()
    for index, vertex in enumerate(obj.data.vertices):
        world = interim[obj][index]
        base = vertex_base_centres[obj][index]
        world.x += base.x * (x_centreline_factor - 1.0)
        world.y += base.y * (y_centreline_factor - 1.0)
        vertex.co = inverse @ world
    obj.data.update()

body_after = {obj.name: object_signature(obj) for obj in body_objects}
if body_before != body_after:
    raise RuntimeError("A non-rim basket object changed during rim refinement")

bpy.context.view_layer.update()
new_bounds = [world_bounds(obj) for obj in rim_objects]
new_bottom = min(bounds[4] for bounds in new_bounds)
new_top = max(bounds[5] for bounds in new_bounds)

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

print(f"Rim objects refined: {[obj.name for obj in rim_objects]}")
print(f"Body objects unchanged: {len(body_objects)}")
print(f"Wall top: {wall_top:.5f}")
print(f"Rim bounds before: {old_bottom:.5f} .. {old_top:.5f}")
print(f"Rim bounds after:  {new_bottom:.5f} .. {new_top:.5f}")
print(f"New rim height: {new_top - new_bottom:.5f}")
print(f"Rim radial thickness factor: {radial_thickness_factor:.3f}")
print(f"Rim centreline alignment factors: X {x_centreline_factor:.5f}, Y {y_centreline_factor:.5f}")
