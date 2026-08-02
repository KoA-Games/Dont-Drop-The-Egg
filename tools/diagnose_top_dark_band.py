import bpy
import os
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT_DIR = os.path.join(ROOT, "assets", "basket", "top_band_diagnostics")
os.makedirs(OUT_DIR, exist_ok=True)


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


scene = bpy.context.scene
camera = scene.camera
camera.location = (0.0, -5.50, 0.96)
camera.data.lens = 60
look_at(camera, (0.0, -1.00, 0.755))
scene.render.resolution_x = 1200
scene.render.resolution_y = 420
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"

core = bpy.data.objects["ContinuousSoftTopRim"]
twists = [bpy.data.objects["RimDiagonalTwist_1"], bpy.data.objects["RimDiagonalTwist_2"]]
front_top = bpy.data.objects["FrontBackHorizontalRibbon_-1_7"]
front_panel = bpy.data.objects["FrontSolidWovenPanel"]
rim_objects = [core, *twists]


def render(name):
    scene.render.filepath = os.path.join(OUT_DIR, name + ".png")
    bpy.ops.render.render(write_still=True)
    print(f"Rendered {name}")


def set_hidden(objects, value):
    for obj in objects:
        obj.hide_render = value


render("00_baseline")

core.hide_render = True
render("01_core_rim_hidden")
core.hide_render = False

set_hidden(twists, True)
render("02_wrap_strands_hidden")
set_hidden(twists, False)

front_top.hide_render = True
render("03_front_top_ribbon_hidden")
front_top.hide_render = False

front_panel.hide_render = True
render("04_front_solid_panel_hidden")
front_panel.hide_render = False

# Isolate the lower third of the rim as an explicit face group and make only
# that group transparent.  If the stripe disappears, the source is the rim
# underside itself rather than the wall material or general lighting.
z_values = [
    (obj.matrix_world @ vertex.co).z
    for obj in rim_objects for vertex in obj.data.vertices
]
bottom, top = min(z_values), max(z_values)
limit = bottom + (top - bottom) * 0.34
transparent = bpy.data.materials.new("DIAGNOSTIC Transparent Rim Underside")
transparent.use_nodes = True
nodes = transparent.node_tree.nodes
links = transparent.node_tree.links
nodes.clear()
output = nodes.new("ShaderNodeOutputMaterial")
shader = nodes.new("ShaderNodeBsdfTransparent")
links.new(shader.outputs["BSDF"], output.inputs["Surface"])
transparent.surface_render_method = "DITHERED"

old_assignments = {}
for obj in rim_objects:
    slot = len(obj.data.materials)
    obj.data.materials.append(transparent)
    old_assignments[obj] = [polygon.material_index for polygon in obj.data.polygons]
    normal_matrix = obj.matrix_world.to_3x3()
    for polygon in obj.data.polygons:
        centre_z = sum(
            (obj.matrix_world @ obj.data.vertices[index].co).z
            for index in polygon.vertices
        ) / len(polygon.vertices)
        normal_z = (normal_matrix @ polygon.normal).normalized().z
        if centre_z <= limit and normal_z < 0.28:
            polygon.material_index = slot
render("05_rim_underside_transparent")

for obj, assignments in old_assignments.items():
    for polygon, material_index in zip(obj.data.polygons, assignments):
        polygon.material_index = material_index

print(f"Diagnostic renders saved in {OUT_DIR}")
