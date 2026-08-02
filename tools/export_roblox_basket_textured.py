import hashlib
import math
import os
import struct

import bpy
import numpy as np


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SOURCE_BLEND = os.path.join(
    ROOT, "assets", "basket", "LowWideWovenBasket_RobloxOptimized.blend"
)
OUTPUT_BLEND = os.path.join(
    ROOT, "assets", "basket", "LowWideWovenBasket_RobloxTextured.blend"
)
OUTPUT_FBX = os.path.join(
    ROOT, "assets", "basket", "LowWideWovenBasket_RobloxTextured.fbx"
)
OUTPUT_TEXTURE = os.path.join(
    ROOT, "assets", "basket", "DefaultBasket_V1_BaseColor.png"
)
OBJECT_NAME = "LowWideWovenBasket_RobloxOptimized"
TEXTURE_SIZE = 1024
ATLAS_COLUMNS = 4
ATLAS_ROWS = 4


def brighten_wicker_color(color):
    """Lift the old chocolate-dark palette into a medium warm wicker range."""
    return (
        min(1.0, color[0] * 1.35 + 0.16),
        min(1.0, color[1] * 1.45 + 0.10),
        min(1.0, color[2] * 1.55 + 0.055),
    )


def mesh_geometry_hash(mesh):
    digest = hashlib.sha256()
    for vertex in mesh.vertices:
        digest.update(struct.pack("<3f", *vertex.co))
    for polygon in mesh.polygons:
        digest.update(struct.pack("<I", len(polygon.vertices)))
        for vertex_index in polygon.vertices:
            digest.update(struct.pack("<I", vertex_index))
    return digest.hexdigest()


def build_base_color_atlas(colors):
    image = bpy.data.images.get("DefaultBasket_V1_BaseColor")
    if image is not None:
        bpy.data.images.remove(image)
    image = bpy.data.images.new(
        "DefaultBasket_V1_BaseColor",
        width=TEXTURE_SIZE,
        height=TEXTURE_SIZE,
        alpha=True,
        float_buffer=False,
    )
    image.colorspace_settings.name = "sRGB"

    pixels = np.zeros((TEXTURE_SIZE, TEXTURE_SIZE, 4), dtype=np.float32)
    pixels[:, :, 3] = 1.0
    tile_width = TEXTURE_SIZE // ATLAS_COLUMNS
    tile_height = TEXTURE_SIZE // ATLAS_ROWS
    rng = np.random.default_rng(481516)

    average = np.mean(np.asarray(colors, dtype=np.float32), axis=0)
    tile_colors = list(colors) + [tuple(average)] * (
        ATLAS_COLUMNS * ATLAS_ROWS - len(colors)
    )

    for material_index, base_color in enumerate(tile_colors):
        column = material_index % ATLAS_COLUMNS
        row = material_index // ATLAS_COLUMNS
        x0 = column * tile_width
        y0 = row * tile_height
        x1 = x0 + tile_width
        y1 = y0 + tile_height

        yy, xx = np.mgrid[0:tile_height, 0:tile_width]
        # Small, dry fiber variation. The geometry remains responsible for the
        # actual weave; this only prevents flat white/default shading in Roblox.
        long_fiber = np.sin((xx * 0.105) + (yy * 0.018) + material_index * 0.73)
        fine_fiber = np.sin((xx * 0.33) - (yy * 0.035) + material_index * 1.31)
        mottling = rng.normal(0.0, 1.0, (tile_height, tile_width))
        variation = 1.0 + long_fiber * 0.035 + fine_fiber * 0.012 + mottling * 0.008
        warm_shift = np.stack(
            (
                long_fiber * 0.007,
                fine_fiber * 0.002,
                -long_fiber * 0.002,
            ),
            axis=-1,
        )
        rgb = np.asarray(base_color, dtype=np.float32)[None, None, :]
        tile = np.clip(rgb * variation[:, :, None] + warm_shift, 0.0, 1.0)
        pixels[y0:y1, x0:x1, :3] = tile

    image.pixels.foreach_set(pixels.reshape(-1))
    image.filepath_raw = OUTPUT_TEXTURE
    image.file_format = "PNG"
    image.save()
    # Keep the image external. Roblox Studio can fail to resolve Blender's
    # embedded .fbm payload even though the FBX itself is valid; a stripped,
    # relative filename beside the FBX is the most portable import path.
    image.filepath = OUTPUT_TEXTURE
    return image


def load_existing_base_color():
    image = bpy.data.images.get("DefaultBasket_V1_BaseColor")
    if image is not None:
        bpy.data.images.remove(image)
    image = bpy.data.images.load(OUTPUT_TEXTURE, check_existing=False)
    image.name = "DefaultBasket_V1_BaseColor"
    image.colorspace_settings.name = "sRGB"
    return image


def rebuild_uv_atlas(mesh, original_material_indices):
    while mesh.uv_layers:
        mesh.uv_layers.remove(mesh.uv_layers[0])
    uv_layer = mesh.uv_layers.new(name="UVMap")

    coordinates = np.asarray([vertex.co[:] for vertex in mesh.vertices])
    minimum = coordinates.min(axis=0)
    maximum = coordinates.max(axis=0)
    span = np.maximum(maximum - minimum, 1.0e-6)
    margin = 0.045

    for polygon, material_index in zip(mesh.polygons, original_material_indices):
        tile_index = min(material_index, ATLAS_COLUMNS * ATLAS_ROWS - 1)
        column = tile_index % ATLAS_COLUMNS
        row = tile_index // ATLAS_COLUMNS
        normal = polygon.normal
        dominant_axis = max(range(3), key=lambda axis: abs(normal[axis]))

        for loop_index in polygon.loop_indices:
            coordinate = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            if dominant_axis == 0:
                local_u = (coordinate.y - minimum[1]) / span[1]
                local_v = (coordinate.z - minimum[2]) / span[2]
            elif dominant_axis == 1:
                local_u = (coordinate.x - minimum[0]) / span[0]
                local_v = (coordinate.z - minimum[2]) / span[2]
            else:
                local_u = (coordinate.x - minimum[0]) / span[0]
                local_v = (coordinate.y - minimum[1]) / span[1]

            local_u = margin + float(local_u) * (1.0 - 2.0 * margin)
            local_v = margin + float(local_v) * (1.0 - 2.0 * margin)
            uv_layer.data[loop_index].uv = (
                (column + local_u) / ATLAS_COLUMNS,
                (row + local_v) / ATLAS_ROWS,
            )
    mesh.uv_layers.active = uv_layer
    return uv_layer


def linear_to_srgb(value):
    value = max(0.0, min(1.0, float(value)))
    if value <= 0.0031308:
        return 12.92 * value
    return 1.055 * (value ** (1.0 / 2.4)) - 0.055


def build_fallback_vertex_colors(mesh, original_material_indices, colors):
    # Roblox supports FBX vertex colors. This is a deliberate fallback so the
    # basket remains brown even if Studio declines to upload the PNG texture.
    while mesh.color_attributes:
        mesh.color_attributes.remove(mesh.color_attributes[0])
    attribute = mesh.color_attributes.new(
        name="BasketColor",
        type="BYTE_COLOR",
        domain="CORNER",
    )
    for polygon, material_index in zip(mesh.polygons, original_material_indices):
        source = colors[min(material_index, len(colors) - 1)]
        srgb = tuple(linear_to_srgb(channel) for channel in source)
        for loop_index in polygon.loop_indices:
            attribute.data[loop_index].color_srgb = (*srgb, 1.0)
    mesh.color_attributes.active_color = attribute
    return attribute


def build_roblox_material(image):
    material = bpy.data.materials.get("DefaultBasket_V1")
    if material is None:
        material = bpy.data.materials.new("DefaultBasket_V1")
    material.use_nodes = True
    # The texture already contains the complete wood color. Keeping this white
    # prevents FBX importers from multiplying a second dark material tint over it.
    material.diffuse_color = (1.0, 1.0, 1.0, 1.0)

    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    output.location = (360, 0)
    principled = nodes.new("ShaderNodeBsdfPrincipled")
    principled.location = (80, 0)
    texture = nodes.new("ShaderNodeTexImage")
    texture.location = (-260, 40)
    texture.image = image
    texture.interpolation = "Linear"
    texture.extension = "REPEAT"

    principled.inputs["Roughness"].default_value = 0.82
    principled.inputs["Metallic"].default_value = 0.0
    specular_input = principled.inputs.get("Specular IOR Level")
    if specular_input is not None:
        specular_input.default_value = 0.22
    links.new(texture.outputs["Color"], principled.inputs["Base Color"])
    links.new(principled.outputs["BSDF"], output.inputs["Surface"])
    return material


def validate_uvs(mesh):
    uv_layer = mesh.uv_layers.get("UVMap")
    assert uv_layer is not None, "UVMap is missing"
    assert len(uv_layer.data) == len(mesh.loops), "UV loop count mismatch"
    values = np.asarray([loop.uv[:] for loop in uv_layer.data], dtype=np.float64)
    assert np.isfinite(values).all(), "UVMap contains invalid values"
    assert values.min() >= -1.0e-6 and values.max() <= 1.0 + 1.0e-6, "UVs outside atlas"
    assert np.ptp(values[:, 0]) > 0.1 and np.ptp(values[:, 1]) > 0.1, "UVMap is degenerate"


def export_textured_basket():
    bpy.ops.wm.open_mainfile(filepath=SOURCE_BLEND)
    basket = bpy.data.objects.get(OBJECT_NAME)
    if basket is None or basket.type != "MESH":
        raise RuntimeError(f"Mesh object {OBJECT_NAME!r} was not found")

    mesh = basket.data
    mesh.calc_loop_triangles()
    original_dimensions = tuple(basket.dimensions)
    original_vertex_count = len(mesh.vertices)
    original_polygon_count = len(mesh.polygons)
    original_hash = mesh_geometry_hash(mesh)
    original_material_indices = [polygon.material_index for polygon in mesh.polygons]
    colors = [tuple(material.diffuse_color[:3]) for material in mesh.materials]
    if not colors:
        raise RuntimeError("Basket has no source material colors")

    roblox_colors = [brighten_wicker_color(color) for color in colors]

    if os.environ.get("BASKET_USE_EXISTING_BASE_COLOR") == "1":
        image = load_existing_base_color()
    else:
        image = build_base_color_atlas(roblox_colors)
    rebuild_uv_atlas(mesh, original_material_indices)
    build_fallback_vertex_colors(mesh, original_material_indices, roblox_colors)
    material = build_roblox_material(image)

    mesh.materials.clear()
    mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.material_index = 0
    basket.name = "LowWideWovenBasket_RobloxTextured"
    mesh.name = "LowWideWovenBasket_RobloxTexturedMesh"

    validate_uvs(mesh)
    assert len(mesh.vertices) == original_vertex_count
    assert len(mesh.polygons) == original_polygon_count
    assert mesh_geometry_hash(mesh) == original_hash, "Basket geometry changed"
    assert all(
        math.isclose(before, after, rel_tol=0.0, abs_tol=1.0e-6)
        for before, after in zip(original_dimensions, basket.dimensions)
    ), "Basket dimensions changed"

    bpy.ops.object.select_all(action="DESELECT")
    basket.select_set(True)
    bpy.context.view_layer.objects.active = basket
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND)
    bpy.ops.export_scene.fbx(
        filepath=OUTPUT_FBX,
        use_selection=True,
        object_types={"MESH"},
        global_scale=1.0,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_NONE",
        use_mesh_modifiers=True,
        mesh_smooth_type="FACE",
        use_triangles=True,
        colors_type="SRGB",
        prioritize_active_color=True,
        axis_forward="-Z",
        axis_up="Y",
        path_mode="STRIP",
        embed_textures=False,
        bake_anim=False,
        add_leaf_bones=False,
    )

    print("TEXTURED_BASKET_SOURCE", SOURCE_BLEND)
    print("TEXTURED_BASKET_BLEND", OUTPUT_BLEND)
    print("TEXTURED_BASKET_FBX", OUTPUT_FBX)
    print("TEXTURED_BASKET_TEXTURE", OUTPUT_TEXTURE)
    print("TEXTURED_BASKET_DIMENSIONS", *original_dimensions)
    print("TEXTURED_BASKET_COUNTS", original_vertex_count, original_polygon_count)
    print("TEXTURED_BASKET_GEOMETRY_HASH", original_hash)
    print("TEXTURED_BASKET_UV_LOOPS", len(mesh.uv_layers["UVMap"].data))
    print("TEXTURED_BASKET_MATERIALS", len(mesh.materials))


if __name__ == "__main__":
    export_textured_basket()
