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
    result = []
    for ring in range(PATH_SAMPLES):
        start = ring * size
        points = [
            obj.matrix_world @ obj.data.vertices[index].co
            for index in range(start, start + size)
        ]
        result.append(sum(points, Vector()) / len(points))
    return result


def make_wicker_material(mat, dark, mid, light, bump_strength):
    mat.diffuse_color = (*mid, 1.0)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.88
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.24

    texcoord = nodes.new("ShaderNodeTexCoord")
    coarse = nodes.new("ShaderNodeTexNoise")
    coarse.inputs["Scale"].default_value = 8.5
    coarse.inputs["Detail"].default_value = 5.0
    coarse.inputs["Roughness"].default_value = 0.78
    coarse.inputs["Distortion"].default_value = 0.20
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.25
    ramp.color_ramp.elements[0].color = (*dark, 1.0)
    ramp.color_ramp.elements[1].position = 0.76
    ramp.color_ramp.elements[1].color = (*light, 1.0)
    middle = ramp.color_ramp.elements.new(0.50)
    middle.color = (*mid, 1.0)

    fine = nodes.new("ShaderNodeTexNoise")
    fine.inputs["Scale"].default_value = 68.0
    fine.inputs["Detail"].default_value = 2.4
    fine.inputs["Roughness"].default_value = 0.82
    fine.inputs["Distortion"].default_value = 0.12
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = bump_strength
    bump.inputs["Distance"].default_value = 0.004

    links.new(texcoord.outputs["Generated"], coarse.inputs["Vector"])
    links.new(texcoord.outputs["Generated"], fine.inputs["Vector"])
    links.new(coarse.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(fine.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])


rim_objects = [
    obj for obj in bpy.context.scene.objects
    if obj.type == "MESH" and "Rim" in obj.name
]
core = bpy.data.objects.get("ContinuousSoftTopRim")
twists = [obj for obj in rim_objects if obj.name.startswith("RimDiagonalTwist_")]
if core is None or core not in rim_objects or len(twists) != 2:
    raise RuntimeError("Expected one core rim and two diagonal rim wraps")

body_objects = [
    obj for obj in bpy.context.scene.objects
    if obj.type == "MESH" and obj not in rim_objects
]
body_before = body_fingerprint(body_objects)

old_bounds = [world_bounds(obj) for obj in rim_objects]
old_x = max(max(abs(bounds[0]), abs(bounds[1])) for bounds in old_bounds)
old_y = max(max(abs(bounds[2]), abs(bounds[3])) for bounds in old_bounds)
old_bottom = min(bounds[4] for bounds in old_bounds)
old_top = max(bounds[5] for bounds in old_bounds)

# Preserve the existing 0.020-stud overlap with the wall while making the
# cross-section more obviously oval.  Only the rim vertices are transformed.
target_height = 0.068
z_factor = target_height / (old_top - old_bottom)
overhang_each_side = 0.015
target_x = old_x + overhang_each_side
target_y = old_y + overhang_each_side

# Make the two raised wraps finer and slightly embedded so they read as bound
# wicker fibres instead of dark cords sitting on a polished tube.
core_centres = ring_centres(core)
twist_centres = {obj: ring_centres(obj) for obj in twists}
twist_radius_factor = 0.88
twist_embed_factor = 0.97
for obj in twists:
    size = ring_size(obj)
    inverse = obj.matrix_world.inverted()
    centres = twist_centres[obj]
    for index, vertex in enumerate(obj.data.vertices):
        ring = index // size
        world = obj.matrix_world @ vertex.co
        base = core_centres[ring]
        centre = centres[ring]
        embedded = base + (centre - base) * twist_embed_factor
        world.x = embedded.x + (world.x - centre.x) * twist_radius_factor
        world.y = embedded.y + (world.y - centre.y) * twist_radius_factor
        vertex.co = inverse @ world
    obj.data.update()

# Apply the subtle overhang and final vertical flattening uniformly to all rim
# pieces, keeping the rounded rectangular perimeter and opening intact.
intermediate_bounds = [world_bounds(obj) for obj in rim_objects]
intermediate_x = max(max(abs(bounds[0]), abs(bounds[1])) for bounds in intermediate_bounds)
intermediate_y = max(max(abs(bounds[2]), abs(bounds[3])) for bounds in intermediate_bounds)
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

core_mat = core.data.materials[0]
wrap_mat = twists[0].data.materials[0]
make_wicker_material(
    core_mat,
    dark=(0.17, 0.055, 0.010),
    mid=(0.285, 0.115, 0.025),
    light=(0.41, 0.195, 0.055),
    bump_strength=0.16,
)
make_wicker_material(
    wrap_mat,
    dark=(0.075, 0.016, 0.002),
    mid=(0.155, 0.042, 0.006),
    light=(0.270, 0.105, 0.020),
    bump_strength=0.14,
)

bpy.context.view_layer.update()
body_after = body_fingerprint(body_objects)
if body_before != body_after:
    raise RuntimeError("A non-rim basket mesh changed during rim refinement")

new_bounds = [world_bounds(obj) for obj in rim_objects]
new_x = max(max(abs(bounds[0]), abs(bounds[1])) for bounds in new_bounds)
new_y = max(max(abs(bounds[2]), abs(bounds[3])) for bounds in new_bounds)
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
print(f"Body mesh fingerprint unchanged: {body_after}")
print(f"Rim half-extents before: X {old_x:.5f}, Y {old_y:.5f}")
print(f"Rim half-extents after:  X {new_x:.5f}, Y {new_y:.5f}")
print(f"Rim height before: {old_top - old_bottom:.5f}")
print(f"Rim height after:  {new_top - new_bottom:.5f}")
print(f"Rim bottom preserved at: {new_bottom:.5f}")
print("Rim-only wicker materials rebuilt with coarse colour variation and fine fibre bump")
