import bpy
import os
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "assets", "basket", "LowWideWovenBasket_rim_closeup.png")
scene = bpy.context.scene
camera = scene.camera
camera.location = (0.0, -5.50, 0.96)
camera.data.lens = 60


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


look_at(camera, (0.0, -1.00, 0.755))
scene.render.resolution_x = 1200
scene.render.resolution_y = 420
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print(f"Saved rim close-up: {OUT}")
