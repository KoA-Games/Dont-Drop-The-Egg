import os

import bpy


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ASSET_DIR = os.path.join(ROOT, "assets", "basket")
SOURCE_BLEND = os.path.join(ASSET_DIR, "LowWideWovenBasket.blend")
OUTPUT_BLEND = os.path.join(ASSET_DIR, "LowWideWovenBasket_RobloxOptimized.blend")
OUTPUT_FBX = os.path.join(ASSET_DIR, "LowWideWovenBasket_RobloxOptimized.fbx")
OUTPUT_GLB = os.path.join(ASSET_DIR, "LowWideWovenBasket_RobloxOptimized.glb")
TARGET_TRIANGLES = 42_000


def triangle_count(mesh):
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def material_base_color(material):
    if material is None or not material.use_nodes or material.node_tree is None:
        return None
    principled = material.node_tree.nodes.get("Principled BSDF")
    if principled is None:
        return None
    value = principled.inputs.get("Base Color")
    return tuple(value.default_value) if value else None


def make_roblox_safe_material(material):
    """Replace Blender-only procedural inputs with a dry wicker base color."""
    if material is None or not material.use_nodes or material.node_tree is None:
        return
    principled = material.node_tree.nodes.get("Principled BSDF")
    if principled is None:
        return
    base_color = tuple(material.diffuse_color)
    for link in list(material.node_tree.links):
        if link.to_node == principled and link.to_socket.name in {"Base Color", "Normal"}:
            material.node_tree.links.remove(link)
    principled.inputs["Base Color"].default_value = base_color
    principled.inputs["Roughness"].default_value = 0.72
    if "Metallic" in principled.inputs:
        principled.inputs["Metallic"].default_value = 0.0


def main():
    bpy.ops.wm.open_mainfile(filepath=SOURCE_BLEND)

    visual_objects = [
        obj
        for obj in bpy.context.scene.objects
        if obj.type == "MESH"
        and obj.name != "Plane"
        and not obj.hide_render
    ]
    if not visual_objects:
        raise RuntimeError("No basket visual meshes found")

    bpy.ops.object.select_all(action="DESELECT")
    duplicates = []
    for source in visual_objects:
        duplicate = source.copy()
        duplicate.data = source.data.copy()
        bpy.context.collection.objects.link(duplicate)
        duplicate.select_set(True)
        duplicates.append(duplicate)

    bpy.context.view_layer.objects.active = duplicates[0]
    bpy.ops.object.join()
    basket = bpy.context.object
    basket.name = "LowWideWovenBasket_RobloxOptimized"
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    before = triangle_count(basket.data)
    if before > TARGET_TRIANGLES:
        decimate = basket.modifiers.new("RobloxTriangleBudget", "DECIMATE")
        decimate.decimate_type = "COLLAPSE"
        decimate.ratio = TARGET_TRIANGLES / before
        decimate.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = basket
        bpy.ops.object.modifier_apply(modifier=decimate.name)

    triangulate = basket.modifiers.new("RobloxTriangulation", "TRIANGULATE")
    bpy.context.view_layer.objects.active = basket
    bpy.ops.object.modifier_apply(modifier=triangulate.name)
    after = triangle_count(basket.data)

    # The authored Blender origin is the center of the basket floor. Keeping it
    # here lets Roblox align the imported model directly to Basket.Bottom.
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")

    for polygon in basket.data.polygons:
        polygon.use_smooth = True
    for material in basket.data.materials:
        make_roblox_safe_material(material)

    # Keep only the optimized export object in this derivative file.
    for obj in list(bpy.context.scene.objects):
        if obj != basket:
            bpy.data.objects.remove(obj, do_unlink=True)

    basket.select_set(True)
    bpy.context.view_layer.objects.active = basket
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND)

    bpy.ops.export_scene.fbx(
        filepath=OUTPUT_FBX,
        use_selection=True,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_UNITS",
        axis_forward="-Z",
        axis_up="Y",
        use_mesh_modifiers=True,
        mesh_smooth_type="FACE",
        add_leaf_bones=False,
        bake_anim=False,
    )
    bpy.ops.export_scene.gltf(
        filepath=OUTPUT_GLB,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )

    dimensions = tuple(round(value, 5) for value in basket.dimensions)
    print(f"ROBLOX_BASKET_TRIANGLES_BEFORE={before}")
    print(f"ROBLOX_BASKET_TRIANGLES_AFTER={after}")
    print(f"ROBLOX_BASKET_DIMENSIONS={dimensions}")
    print(f"ROBLOX_BASKET_MATERIALS={len(basket.data.materials)}")
    for index, material in enumerate(basket.data.materials):
        print(
            "ROBLOX_BASKET_MATERIAL",
            index,
            material.name if material else "None",
            material_base_color(material),
        )
    print(f"ROBLOX_BASKET_FBX={OUTPUT_FBX}")
    print(f"ROBLOX_BASKET_GLB={OUTPUT_GLB}")


if __name__ == "__main__":
    main()
