import bpy
import os
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT_DIR = os.path.join(ROOT, "assets", "basket", "top_band_diagnostics")
material = bpy.data.materials["Upper Wall Wicker - Matched Rim Underside"]
bsdf = next(node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
scene = bpy.context.scene
camera = scene.camera
camera.location = (0.0, -5.50, 0.96)
camera.data.lens = 60
camera.rotation_euler = (Vector((0.0, -1.00, 0.755)) - camera.location).to_track_quat("-Z", "Y").to_euler()
scene.render.resolution_x = 1200
scene.render.resolution_y = 420
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"

for strength in (0.45, 0.70, 1.00):
    bsdf.inputs["Emission Strength"].default_value = strength
    name = f"07_match_strength_{str(strength).replace('.', '_')}.png"
    scene.render.filepath = os.path.join(OUT_DIR, name)
    bpy.ops.render.render(write_still=True)
    print(f"Rendered {name}")
