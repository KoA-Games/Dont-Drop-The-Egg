import bpy
import math
import os
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT_DIR = os.path.join(ROOT, "assets", "basket")
BLEND_PATH = os.path.join(OUT_DIR, "LowWideWovenBasket.blend")
FBX_PATH = os.path.join(OUT_DIR, "LowWideWovenBasket_Roblox.fbx")
GLB_PATH = os.path.join(OUT_DIR, "LowWideWovenBasket.glb")
PREVIEW_PATH = os.path.join(OUT_DIR, "LowWideWovenBasket_preview.png")
FRONT_COMPARE_PATH = os.path.join(OUT_DIR, "FrontWeavePrototype_clay_front.png")
ANGLE_COMPARE_PATH = os.path.join(OUT_DIR, "FrontWeavePrototype_clay_angle.png")
INTERIOR_PREVIEW_PATH = os.path.join(OUT_DIR, "LowWideWovenBasket_interior.png")
INTERIOR_WALL_PREVIEW_PATH = os.path.join(
    OUT_DIR, "LowWideWovenBasket_interior_wall.png")

TARGET_W = 2.55
TARGET_D = 2.20
TARGET_H = 0.90
LOWER_W = 2.05
LOWER_D = 1.55
WALL_BOTTOM = 0.085
WALL_TOP = 0.755
PANEL_THICKNESS = 0.050
WOVEN_STRIP_WIDTH = 0.075
WOVEN_STRIP_THICKNESS = 0.012
WALL_HORIZONTAL_WIDTH = 0.075
WALL_VERTICAL_WIDTH = 0.0833
WALL_CROSSING_DEPTH = 0.0058


def reset_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def move_to_collection(obj, collection):
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    collection.objects.link(obj)


def add_editable_bezier_strip(name, coords, bevel_depth, scale, mat, collection):
    curve = bpy.data.curves.new(name + "Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 3
    curve.bevel_depth = bevel_depth
    curve.bevel_resolution = 3
    curve.use_fill_caps = True
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(coords) - 1)
    for point, co in zip(spline.bezier_points, coords):
        point.co = (co.x / scale[0], co.y / scale[1], co.z / scale[2])
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    collection.objects.link(obj)
    obj.scale = scale
    obj.data.materials.append(mat)
    obj["ContinuousStrip"] = True
    obj["EditablePrototype"] = True
    return obj


def front_depth_y(z, relative_depth):
    return -(depth_at(z) * 0.5 + 0.012 + relative_depth)


def add_front_curve_weave_prototype(collection, mat):
    horizontal_count = 7
    vertical_count = 12
    over_depth = 0.017
    under_depth = -0.007
    prototype = []
    row_zs = [
        WALL_BOTTOM + 0.070
        + row * (WALL_TOP - WALL_BOTTOM - 0.140) / (horizontal_count - 1)
        for row in range(horizontal_count)
    ]

    # Seven independent, full-width horizontal Curve objects.
    for row, z in enumerate(row_zs):
        width = width_at(z) - 0.065
        crossing_xs = [
            (-0.46 + 0.92 * column / (vertical_count - 1)) * width_at(z)
            for column in range(vertical_count)
        ]
        spacing = crossing_xs[1] - crossing_xs[0]
        transition_half = spacing * 0.18
        left_end = -width * 0.5
        right_end = width * 0.5
        end_tuck_length = 0.040
        end_tuck_depth = -0.016
        coords = [
            Vector((left_end, front_depth_y(z, end_tuck_depth), z)),
            Vector((left_end + end_tuck_length, front_depth_y(z, 0.0), z)),
        ]
        previous_after = left_end + end_tuck_length
        for column, crossing_x in enumerate(crossing_xs):
            before = max(-width * 0.5, crossing_x - transition_half)
            after = min(width * 0.5, crossing_x + transition_half)
            if before > previous_after + 0.006:
                midpoint = (previous_after + before) * 0.5
                natural_z = z + 0.0012 * math.sin(midpoint * 4.1 + row * 0.73)
                coords.append(Vector((midpoint, front_depth_y(z, 0.0), natural_z)))
            base_depth = over_depth if (row + column) % 2 == 0 else under_depth
            depth = base_depth * (1.0 + 0.04 * math.sin(row * 1.7 + column * 0.9))
            for x in (before, crossing_x, after):
                natural_z = z + 0.0012 * math.sin(x * 4.1 + row * 0.73)
                coords.append(Vector((x, front_depth_y(z, depth), natural_z)))
            previous_after = after
        coords.extend([
            Vector((right_end - end_tuck_length, front_depth_y(z, 0.0), z)),
            Vector((right_end, front_depth_y(z, end_tuck_depth), z)),
        ])
        obj = add_editable_bezier_strip(
            f"FrontHorizontalStrip_{row + 1:02d}", coords,
            0.026, Vector((1.0, 0.30, 1.0)), mat, collection)
        obj["WeaveDirection"] = "Horizontal"
        obj["StripIndex"] = row + 1
        obj["EndTreatment"] = "TuckedBehindCornerSupports"
        if row == 0:
            obj["FloatingStripCorrection"] = "RetainedAndRepositionedOnWall"
        prototype.append(obj)

    # Twelve independent vertical Curve objects that follow the front flare.
    for column in range(vertical_count):
        spacing = row_zs[1] - row_zs[0]
        transition_half = spacing * 0.18
        # Extend only far enough to tuck the reed behind the first/last
        # horizontal bands.  The deeply recessed endpoints hide the round
        # curve caps while preserving one continuous vertical strip.
        z_min = row_zs[0] - transition_half - 0.008
        z_max = row_zs[-1] + transition_half + 0.008
        coords = []

        def vertical_point(z, depth):
            fraction = -0.46 + 0.92 * column / (vertical_count - 1)
            x = fraction * width_at(z) + 0.0010 * math.sin(z * 8.3 + column * 0.67)
            return Vector((x, front_depth_y(z, depth), z))

        coords.append(vertical_point(z_min, -0.032))
        previous_after = z_min
        for row, crossing_z in enumerate(row_zs):
            before = max(z_min, crossing_z - transition_half)
            after = min(z_max, crossing_z + transition_half)
            if before > previous_after + 0.006:
                coords.append(vertical_point((previous_after + before) * 0.5, 0.0))
            base_depth = under_depth if (row + column) % 2 == 0 else over_depth
            depth = base_depth * (1.0 + 0.04 * math.sin(row * 1.7 + column * 0.9))
            coords.extend([
                vertical_point(before, depth),
                vertical_point(crossing_z, depth),
                vertical_point(after, depth),
            ])
            previous_after = after
        coords.append(vertical_point(z_max, -0.032))
        obj = add_editable_bezier_strip(
            f"FrontVerticalStrip_{column + 1:02d}", coords,
            0.026, Vector((1.0, 0.30, 1.0)), mat, collection)
        obj["WeaveDirection"] = "Vertical"
        obj["StripIndex"] = column + 1
        prototype.append(obj)

    return prototype, horizontal_count, vertical_count, over_depth - under_depth


def wicker_material(name, color, texture_strength=0.18, grain_axis=None):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.78
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 13.0
    noise.inputs["Detail"].default_value = 3.5
    noise.inputs["Roughness"].default_value = 0.72
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*(c * (1.0 - texture_strength) for c in color), 1.0)
    ramp.color_ramp.elements[1].color = (*(min(1.0, c * (1.0 + texture_strength)) for c in color), 1.0)
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.10
    bump.inputs["Distance"].default_value = 0.018
    if grain_axis:
        texcoord = nodes.new("ShaderNodeTexCoord")
        mapping = nodes.new("ShaderNodeMapping")
        grain_scales = {
            "X": (2.8, 34.0, 34.0),
            "Y": (34.0, 2.8, 34.0),
            "Z": (34.0, 34.0, 2.8),
        }
        mapping.inputs["Scale"].default_value = grain_scales[grain_axis]
        links.new(texcoord.outputs["Generated"], mapping.inputs["Vector"])
        links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def add_bowed_wicker_reed(name, start, end, z, face_axis, sign, surface, mat):
    """A flattened, capped reed whose center bows slightly away from the wall."""
    vertical_scale = 0.92
    curve = bpy.data.curves.new(name + "Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 2
    curve.bevel_depth = 0.027
    curve.bevel_resolution = 1
    curve.use_fill_caps = True
    spline = curve.splines.new("NURBS")
    spline.points.add(4)
    for i, point in enumerate(spline.points):
        t = i / 4
        along = start + (end - start) * t
        # Ends sit close to the panel; the middle rises outward like a bent
        # wicker strip passing over the recessed vertical layer.
        bow = 0.010 * math.sin(math.pi * t)
        outward_center = sign * (surface + 0.010 + bow)
        if face_axis == "Y":
            co = Vector((along, outward_center, z / vertical_scale))
        else:
            co = Vector((outward_center, along, z / vertical_scale))
        point.co = (*co, 1.0)
    spline.order_u = 3
    spline.use_endpoint_u = True
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.scale.z = vertical_scale
    obj.data.materials.append(mat)
    return obj


def add_vertical_overpass(name, along, z, face_axis, sign, surface, mat):
    if face_axis == "Y":
        slope = math.atan(((TARGET_D - LOWER_D) * 0.5) / (WALL_TOP - WALL_BOTTOM))
        return add_box(
            name, (along, sign * (surface + 0.011), z), (0.034, 0.013, 0.082),
            (-sign * slope, 0, 0), mat, 0.004)
    slope = math.atan(((TARGET_W - LOWER_W) * 0.5) / (WALL_TOP - WALL_BOTTOM))
    return add_box(
        name, (sign * (surface + 0.011), along, z), (0.013, 0.034, 0.082),
        (0, sign * slope, 0), mat, 0.004)


def mesh_object(name, verts, faces, mat, bevel=0.0):
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    if bevel:
        mod = obj.modifiers.new("Soft wicker edge", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        mod.limit_method = "ANGLE"
    return obj


def add_box(name, location, size, rotation, mat, bevel=0.008):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (size[0] * 0.5, size[1] * 0.5, size[2] * 0.5)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if bevel:
        mod = obj.modifiers.new("Soft woven edge", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        mod.limit_method = "ANGLE"
    return obj


def width_at(z):
    t = max(0.0, min(1.0, (z - WALL_BOTTOM) / (WALL_TOP - WALL_BOTTOM)))
    return LOWER_W + (TARGET_W - LOWER_W) * t


def depth_at(z):
    t = max(0.0, min(1.0, (z - WALL_BOTTOM) / (WALL_TOP - WALL_BOTTOM)))
    return LOWER_D + (TARGET_D - LOWER_D) * t


def add_solid_wall_panels(objects, panel_mat):
    # Four real, closed panels define the silhouette. Decorative weave never
    # needs to leave an opening through the basket wall.
    for sign in (-1, 1):
        yl = sign * LOWER_D * 0.5
        yu = sign * TARGET_D * 0.5
        yil = yl - sign * PANEL_THICKNESS
        yiu = yu - sign * PANEL_THICKNESS
        lower_half_w = LOWER_W * 0.5 - 0.045
        upper_half_w = TARGET_W * 0.5 - 0.065
        verts = [
            Vector((-lower_half_w, yl, WALL_BOTTOM)), Vector((lower_half_w, yl, WALL_BOTTOM)),
            Vector((upper_half_w, yu, WALL_TOP)), Vector((-upper_half_w, yu, WALL_TOP)),
            Vector((-lower_half_w, yil, WALL_BOTTOM)), Vector((lower_half_w, yil, WALL_BOTTOM)),
            Vector((upper_half_w, yiu, WALL_TOP)), Vector((-upper_half_w, yiu, WALL_TOP)),
        ]
        faces = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
        objects.append(mesh_object(f"{'Back' if sign > 0 else 'Front'}SolidWovenPanel", verts, faces, panel_mat, 0.012))

    for sign in (-1, 1):
        xl = sign * LOWER_W * 0.5
        xu = sign * TARGET_W * 0.5
        xil = xl - sign * PANEL_THICKNESS
        xiu = xu - sign * PANEL_THICKNESS
        lower_half_d = LOWER_D * 0.5 - 0.045
        upper_half_d = TARGET_D * 0.5 - 0.065
        verts = [
            Vector((xl, -lower_half_d, WALL_BOTTOM)), Vector((xl, lower_half_d, WALL_BOTTOM)),
            Vector((xu, upper_half_d, WALL_TOP)), Vector((xu, -upper_half_d, WALL_TOP)),
            Vector((xil, -lower_half_d, WALL_BOTTOM)), Vector((xil, lower_half_d, WALL_BOTTOM)),
            Vector((xiu, upper_half_d, WALL_TOP)), Vector((xiu, -upper_half_d, WALL_TOP)),
        ]
        faces = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
        objects.append(mesh_object(f"{'Right' if sign > 0 else 'Left'}SolidWovenPanel", verts, faces, panel_mat, 0.012))


def add_curve(name, points, radius, mat, cyclic=False, bevel_resolution=1):
    curve = bpy.data.curves.new(name + "Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 1
    curve.bevel_depth = radius
    curve.bevel_resolution = bevel_resolution
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, co in zip(spline.points, points):
        point.co = (*co, 1.0)
    spline.use_cyclic_u = cyclic
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def add_recessed_vertical_layer(objects, detail_mat):
    # This is the lower visual layer. It is almost flush with the panel and is
    # only seen in the tiny spaces between broad horizontal bands.
    for sign in (-1, 1):
        for i in range(15):
            f = -0.46 + 0.92 * i / 14
            points = []
            for step in range(5):
                z = WALL_BOTTOM + 0.018 + (WALL_TOP - WALL_BOTTOM - 0.036) * step / 4
                points.append(Vector((f * width_at(z), sign * (depth_at(z) * 0.5 + 0.004), z)))
            objects.append(add_curve(f"FrontBackRecessedReed_{sign}_{i}", points, 0.008, detail_mat))
    for sign in (-1, 1):
        for i in range(11):
            f = -0.45 + 0.90 * i / 10
            points = []
            for step in range(5):
                z = WALL_BOTTOM + 0.018 + (WALL_TOP - WALL_BOTTOM - 0.036) * step / 4
                points.append(Vector((sign * (width_at(z) * 0.5 + 0.004), f * depth_at(z), z)))
            objects.append(add_curve(f"SideRecessedReed_{sign}_{i}", points, 0.008, detail_mat))


def add_front_back_surface_weave(objects, sign, row, z, mats):
    full_w = width_at(z)
    w = full_w - 0.13
    d = depth_at(z)
    gap = 0.010
    length_pattern = (0.40, 0.26, 0.34, 0.29)
    cursor = -w * 0.5 - (0.15 if row % 2 else 0.0)
    index = row % len(length_pattern)
    part = 0
    while cursor < w * 0.5:
        length = length_pattern[index % len(length_pattern)]
        left = max(-w * 0.5, cursor)
        right = min(w * 0.5, cursor + length)
        if right - left > 0.060:
            objects.append(add_bowed_wicker_reed(
                f"FrontBackBowedBand_{sign}_{row}_{part}", left, right, z,
                "Y", sign, d * 0.5, mats[(row + part) % len(mats)]))
        cursor += length + gap
        index += 1
        part += 1


def add_side_surface_weave(objects, sign, row, z, mats):
    w = width_at(z)
    d = depth_at(z) - 0.13
    gap = 0.010
    length_pattern = (0.31, 0.23, 0.28, 0.25)
    cursor = -d * 0.5 - (0.12 if row % 2 else 0.0)
    index = row % len(length_pattern)
    part = 0
    while cursor < d * 0.5:
        length = length_pattern[index % len(length_pattern)]
        low = max(-d * 0.5, cursor)
        high = min(d * 0.5, cursor + length)
        if high - low > 0.060:
            objects.append(add_bowed_wicker_reed(
                f"SideBowedBand_{sign}_{row}_{part}", low, high, z,
                "X", sign, w * 0.5, mats[(row + part + 1) % len(mats)]))
        cursor += length + gap
        index += 1
        part += 1


def add_surface_weave(objects, front_mats, side_mats, overpass_mat):
    rows = 10
    row_zs = []
    for row in range(rows):
        z = WALL_BOTTOM + 0.040 + row * (WALL_TOP - WALL_BOTTOM - 0.080) / (rows - 1)
        row_zs.append(z)
        for sign in (-1, 1):
            add_front_back_surface_weave(objects, sign, row, z, front_mats)
            add_side_surface_weave(objects, sign, row, z, side_mats)

    # Selective vertical overpasses interrupt the horizontal seams. They are a
    # shallow third layer, giving a clear under/over read without opening holes.
    for boundary in range(rows - 1):
        z = (row_zs[boundary] + row_zs[boundary + 1]) * 0.5
        w = width_at(z) - 0.18
        d = depth_at(z) - 0.18
        for sign in (-1, 1):
            for j in range(11):
                if (j + boundary) % 3 != 0:
                    continue
                x = -w * 0.5 + (j + 0.5) * w / 11
                objects.append(add_vertical_overpass(
                    f"FrontBackOverpass_{sign}_{boundary}_{j}", x, z, "Y", sign,
                    depth_at(z) * 0.5, overpass_mat))
            for j in range(8):
                if (j + boundary) % 3 != 1:
                    continue
                y = -d * 0.5 + (j + 0.5) * d / 8
                objects.append(add_vertical_overpass(
                    f"SideOverpass_{sign}_{boundary}_{j}", y, z, "X", sign,
                    width_at(z) * 0.5, overpass_mat))


def add_flat_vertical_wicker(name, points, face_axis, mat):
    curve = bpy.data.curves.new(name + "Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 1
    curve.bevel_depth = 0.016
    curve.bevel_resolution = 1
    curve.use_fill_caps = True
    spline = curve.splines.new("NURBS")
    spline.points.add(len(points) - 1)
    flatten = 0.55
    for point, co in zip(spline.points, points):
        if face_axis == "Y":
            point.co = (co.x, co.y / flatten, co.z, 1.0)
        else:
            point.co = (co.x / flatten, co.y, co.z, 1.0)
    spline.order_u = 3
    spline.use_endpoint_u = True
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    if face_axis == "Y":
        obj.scale.y = flatten
    else:
        obj.scale.x = flatten
    obj.data.materials.append(mat)
    return obj


def add_continuous_horizontal_wicker(name, sign, z, face_axis, stake_count, mat):
    vertical_scale = 0.88
    samples = (stake_count - 1) * 2 + 1
    curve = bpy.data.curves.new(name + "Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 1
    curve.bevel_depth = 0.030
    curve.bevel_resolution = 1
    curve.use_fill_caps = True
    spline = curve.splines.new("NURBS")
    spline.points.add(samples - 1)
    row = int(name.rsplit("_", 1)[-1])
    if face_axis == "Y":
        span = width_at(z) - 0.12
        surface = depth_at(z) * 0.5
    else:
        span = depth_at(z) - 0.12
        surface = width_at(z) * 0.5
    for i, point in enumerate(spline.points):
        u = i / (samples - 1)
        along = -span * 0.5 + span * u
        crossing = math.cos(math.pi * (stake_count - 1) * u + row * math.pi)
        outward = sign * (surface + 0.004 + 0.020 * crossing)
        if face_axis == "Y":
            point.co = (along, outward, z / vertical_scale, 1.0)
        else:
            point.co = (outward, along, z / vertical_scale, 1.0)
    spline.order_u = 3
    spline.use_endpoint_u = True
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.scale.z = vertical_scale
    obj.data.materials.append(mat)
    return obj


def add_interwoven_strip_surface(objects, front_mats, side_mats, vertical_mat):
    # Long vertical strips run continuously from bottom to rim.
    front_stakes = 15
    side_stakes = 11
    for sign in (-1, 1):
        for i in range(front_stakes):
            fraction = -0.46 + 0.92 * i / (front_stakes - 1)
            points = []
            for step in range(7):
                z = WALL_BOTTOM + 0.018 + (WALL_TOP - WALL_BOTTOM - 0.036) * step / 6
                points.append(Vector((
                    fraction * width_at(z),
                    sign * (depth_at(z) * 0.5 + 0.010),
                    z,
                )))
            objects.append(add_flat_vertical_wicker(
                f"FrontBackContinuousVertical_{sign}_{i}", points, "Y", vertical_mat))
        for i in range(side_stakes):
            fraction = -0.45 + 0.90 * i / (side_stakes - 1)
            points = []
            for step in range(7):
                z = WALL_BOTTOM + 0.018 + (WALL_TOP - WALL_BOTTOM - 0.036) * step / 6
                points.append(Vector((
                    sign * (width_at(z) * 0.5 + 0.010),
                    fraction * depth_at(z),
                    z,
                )))
            objects.append(add_flat_vertical_wicker(
                f"SideContinuousVertical_{sign}_{i}", points, "X", vertical_mat))

    # Every horizontal course is one uninterrupted strip per wall. The strip
    # alternates behind/in front of successive verticals, and adjacent rows
    # invert that rhythm.
    rows = 10
    for row in range(rows):
        z = WALL_BOTTOM + 0.042 + row * (WALL_TOP - WALL_BOTTOM - 0.084) / (rows - 1)
        for sign in (-1, 1):
            objects.append(add_continuous_horizontal_wicker(
                f"FrontBackContinuousHorizontal_{sign}_{row}", sign, z, "Y",
                front_stakes, front_mats[row % len(front_mats)]))
            objects.append(add_continuous_horizontal_wicker(
                f"SideContinuousHorizontal_{sign}_{row}", sign, z, "X",
                side_stakes, side_mats[row % len(side_mats)]))


def woven_relief(u, v, columns, rows):
    row_value = min(rows - 1.0e-6, v * rows)
    row = int(math.floor(row_value))
    row_fraction = row_value - row
    # Every course starts at a subtly different point and meanders by a tiny
    # amount, avoiding a mechanically repeated grid while remaining clean.
    row_shift = 0.18 * math.sin(row * 1.73) + (0.16 if row % 2 else 0.0)
    column_value = u * columns + row_shift
    column = int(math.floor(column_value))
    column_fraction = column_value - column
    row_fraction += 0.022 * math.sin(u * math.tau * 2.0 + row * 0.91)
    def rounded_band(fraction, half_width, edge_softness):
        distance = abs(fraction - 0.5)
        value = max(0.0, min(1.0, (half_width - distance) / edge_softness))
        return value * value * (3.0 - 2.0 * value)

    horizontal = rounded_band(row_fraction, 0.43, 0.105)
    vertical = rounded_band(column_fraction, 0.24, 0.085)
    natural_variation = 0.94 + 0.06 * math.sin(column * 2.17 + row * 1.31)
    # Alternate which embossed band is uppermost at every crossing. Because
    # this is one continuous surface, no pipes, blocks, holes, or loose pieces
    # are created.
    if (column + row) % 2 == 0:
        return 0.002 + natural_variation * (
            0.016 * horizontal + 0.003 * vertical * (1.0 - horizontal)
        )
    return 0.002 + natural_variation * (0.007 * horizontal + 0.016 * vertical)


def add_embossed_front_back_surface(objects, sign, mat):
    x_steps = 106
    z_steps = 61
    columns = 15
    rows = 10
    verts = []
    faces = []
    for j in range(z_steps):
        v = j / (z_steps - 1)
        z = WALL_BOTTOM + 0.012 + (WALL_TOP - WALL_BOTTOM - 0.024) * v
        span = width_at(z) - 0.06
        for i in range(x_steps):
            u = i / (x_steps - 1)
            x = -span * 0.5 + span * u
            y = sign * (depth_at(z) * 0.5 + woven_relief(u, v, columns, rows))
            verts.append(Vector((x, y, z)))
    for j in range(z_steps - 1):
        for i in range(x_steps - 1):
            a = j * x_steps + i
            faces.append((a, a + 1, a + 1 + x_steps, a + x_steps))
    obj = mesh_object(f"{'Back' if sign > 0 else 'Front'}IntegratedWovenRelief", verts, faces, mat)
    objects.append(obj)


def add_embossed_side_surface(objects, sign, mat):
    y_steps = 78
    z_steps = 61
    columns = 11
    rows = 10
    verts = []
    faces = []
    for j in range(z_steps):
        v = j / (z_steps - 1)
        z = WALL_BOTTOM + 0.012 + (WALL_TOP - WALL_BOTTOM - 0.024) * v
        span = depth_at(z) - 0.06
        for i in range(y_steps):
            u = i / (y_steps - 1)
            y = -span * 0.5 + span * u
            x = sign * (width_at(z) * 0.5 + woven_relief(u, v, columns, rows))
            verts.append(Vector((x, y, z)))
    for j in range(z_steps - 1):
        for i in range(y_steps - 1):
            a = j * y_steps + i
            faces.append((a, a + 1, a + 1 + y_steps, a + y_steps))
    obj = mesh_object(f"{'Right' if sign > 0 else 'Left'}IntegratedWovenRelief", verts, faces, mat)
    objects.append(obj)


def add_embossed_woven_surface(objects, front_mat, side_mat):
    for sign in (-1, 1):
        add_embossed_front_back_surface(objects, sign, front_mat)
        add_embossed_side_surface(objects, sign, side_mat)


def add_inner_woven_liners(objects, front_mat, side_mat):
    """Closed-looking woven relief for all four interior wall faces."""
    rows = 7
    wall_cell = (WALL_TOP - WALL_BOTTOM - 0.084) / (rows - 1)
    middle_z = (WALL_BOTTOM + WALL_TOP) * 0.5
    front_columns = round((width_at(middle_z) - 0.08) / wall_cell) + 1
    side_columns = round((depth_at(middle_z) - 0.08) / wall_cell) + 1
    z_steps = rows * 6 + 1

    for sign in (-1, 1):
        x_steps = front_columns * 4 + 1
        verts = []
        faces = []
        for j in range(z_steps):
            v = j / (z_steps - 1)
            z = WALL_BOTTOM + 0.006 + (WALL_TOP - WALL_BOTTOM - 0.012) * v
            span = width_at(z) - 0.08
            for i in range(x_steps):
                u = i / (x_steps - 1)
                x = -span * 0.5 + span * u
                # Smaller radial distance moves the relief toward the basket
                # interior.  The modulation is real geometry, not a flat wall.
                radial = depth_at(z) * 0.5 - 0.030 - woven_relief(
                    u, v, front_columns, rows)
                verts.append(Vector((x, sign * radial, z)))
        for j in range(z_steps - 1):
            for i in range(x_steps - 1):
                a = j * x_steps + i
                faces.append((a, a + 1, a + 1 + x_steps, a + x_steps))
        objects.append(mesh_object(
            f"{'Back' if sign > 0 else 'Front'}InnerWovenLiner",
            verts, faces, front_mat))

    for sign in (-1, 1):
        y_steps = side_columns * 4 + 1
        verts = []
        faces = []
        for j in range(z_steps):
            v = j / (z_steps - 1)
            z = WALL_BOTTOM + 0.006 + (WALL_TOP - WALL_BOTTOM - 0.012) * v
            span = depth_at(z) - 0.08
            for i in range(y_steps):
                u = i / (y_steps - 1)
                y = -span * 0.5 + span * u
                radial = width_at(z) * 0.5 - 0.030 - woven_relief(
                    u, v, side_columns, rows)
                verts.append(Vector((sign * radial, y, z)))
        for j in range(z_steps - 1):
            for i in range(y_steps - 1):
                a = j * y_steps + i
                faces.append((a, a + 1, a + 1 + y_steps, a + y_steps))
        objects.append(mesh_object(
            f"{'Right' if sign > 0 else 'Left'}InnerWovenLiner",
            verts, faces, side_mat))


def add_closed_ribbon_mesh(name, sections, mat, bevel=0.0045):
    verts = [vertex for section in sections for vertex in section]
    faces = []
    count = len(sections)
    faces.append((0, 1, 2, 3))
    last = (count - 1) * 4
    faces.append((last + 3, last + 2, last + 1, last))
    for i in range(count - 1):
        a = i * 4
        b = (i + 1) * 4
        faces.extend([
            (a, b, b + 1, a + 1),
            (a + 1, b + 1, b + 2, a + 2),
            (a + 2, b + 2, b + 3, a + 3),
            (a + 3, b + 3, b, a),
        ])
    return mesh_object(name, verts, faces, mat, bevel)


def add_layered_horizontal_ribbon(
        objects, sign, row, z, face_axis, columns, mat, interior=False):
    samples = (columns - 1) * 8 + 1
    strip_height = WALL_HORIZONTAL_WIDTH
    strip_thickness = WOVEN_STRIP_THICKNESS
    baseline = 0.015
    crossing_depth = WALL_CROSSING_DEPTH
    sections = []
    if face_axis == "Y":
        span = width_at(z) - 0.08
        surface = depth_at(z) * 0.5
    else:
        span = depth_at(z) - 0.08
        surface = width_at(z) * 0.5
    for i in range(samples):
        u = i / (samples - 1)
        along = -span * 0.5 + span * u
        # A full smooth S-curve through every crossing keeps the ribbon
        # visually continuous.  Localized peaks made the exposed portions
        # resemble separate armour plates.
        crossing = math.cos(
            math.pi * (columns - 1) * u + row * math.pi)
        layer_surface = surface - PANEL_THICKNESS if interior else surface
        center = (layer_surface + (-baseline if interior else baseline)
                  + crossing_depth * crossing)
        inner = sign * (center - strip_thickness * 0.5)
        outer = sign * (center + strip_thickness * 0.5)
        if face_axis == "Y":
            sections.append([
                Vector((along, inner, z - strip_height * 0.5)),
                Vector((along, outer, z - strip_height * 0.5)),
                Vector((along, outer, z + strip_height * 0.5)),
                Vector((along, inner, z + strip_height * 0.5)),
            ])
        else:
            sections.append([
                Vector((inner, along, z - strip_height * 0.5)),
                Vector((outer, along, z - strip_height * 0.5)),
                Vector((outer, along, z + strip_height * 0.5)),
                Vector((inner, along, z + strip_height * 0.5)),
            ])
    objects.append(add_closed_ribbon_mesh(
        f"{'Inner' if interior else ''}{'FrontBack' if face_axis == 'Y' else 'Side'}HorizontalRibbon_{sign}_{row}",
        sections, mat))


def add_layered_vertical_ribbon(
        objects, sign, column, columns, rows, face_axis, mat, interior=False):
    samples = (rows - 1) * 8 + 1
    # The vertical stake remains continuous but is narrower than the dominant
    # horizontal courses, matching the dense reference basket language.
    strip_width = WALL_VERTICAL_WIDTH
    strip_thickness = WOVEN_STRIP_THICKNESS
    baseline = 0.015
    crossing_depth = WALL_CROSSING_DEPTH
    z_min = WALL_BOTTOM + 0.042
    z_max = WALL_TOP - 0.042
    sections = []
    for i in range(samples):
        t = i / (samples - 1)
        z = z_min + (z_max - z_min) * t
        crossing = math.cos(
            math.pi * (rows - 1) * t + column * math.pi)
        if face_axis == "Y":
            span = width_at(z) - 0.08
            along = -span * 0.5 + span * column / (columns - 1)
            surface = depth_at(z) * 0.5
        else:
            span = depth_at(z) - 0.08
            along = -span * 0.5 + span * column / (columns - 1)
            surface = width_at(z) * 0.5
        # Exact inverse of the horizontal depth at the same parity.
        layer_surface = surface - PANEL_THICKNESS if interior else surface
        center = (layer_surface + (-baseline if interior else baseline)
                  - crossing_depth * crossing)
        inner = sign * (center - strip_thickness * 0.5)
        outer = sign * (center + strip_thickness * 0.5)
        if face_axis == "Y":
            sections.append([
                Vector((along - strip_width * 0.5, inner, z)),
                Vector((along + strip_width * 0.5, inner, z)),
                Vector((along + strip_width * 0.5, outer, z)),
                Vector((along - strip_width * 0.5, outer, z)),
            ])
        else:
            sections.append([
                Vector((inner, along - strip_width * 0.5, z)),
                Vector((outer, along - strip_width * 0.5, z)),
                Vector((outer, along + strip_width * 0.5, z)),
                Vector((inner, along + strip_width * 0.5, z)),
            ])
    objects.append(add_closed_ribbon_mesh(
        f"{'Inner' if interior else ''}{'FrontBack' if face_axis == 'Y' else 'Side'}VerticalRibbon_{sign}_{column}",
        sections, mat, 0.0045))


def add_true_layered_weave(objects, front_mats, side_mats, vertical_mat):
    # Use an approximately square crossing grid.  At the wall midpoint, the
    # exposed horizontal span between two verticals is the same length as the
    # exposed vertical span between two horizontals.  Each visible piece now
    # has the same dimensions after a 90-degree rotation.
    rows = 8
    front_columns = 11
    side_columns = 9
    row_zs = [
        WALL_BOTTOM + 0.042
        + row * (WALL_TOP - WALL_BOTTOM - 0.084) / (rows - 1)
        for row in range(rows)
    ]
    for interior in (False, True):
        for sign in (-1, 1):
            for column in range(front_columns):
                add_layered_vertical_ribbon(
                    objects, sign, column, front_columns, rows, "Y",
                    vertical_mat, interior)
            for column in range(side_columns):
                add_layered_vertical_ribbon(
                    objects, sign, column, side_columns, rows, "X",
                    vertical_mat, interior)
        for row, z in enumerate(row_zs):
            for sign in (-1, 1):
                add_layered_horizontal_ribbon(
                    objects, sign, row, z, "Y", front_columns,
                    front_mats[row % len(front_mats)], interior)
                add_layered_horizontal_ribbon(
                    objects, sign, row, z, "X", side_columns,
                    side_mats[row % len(side_mats)], interior)


def add_outer_vertical_continuity_bridges(objects, vertical_mat):
    """Shorten only the visually hidden part of each outer vertical stake.

    The authored vertical ribbons remain continuous.  These flush bridge
    faces extend their visible upper/lower edges across an overpassing
    horizontal course, leaving a narrow horizontal seam at the crossing.
    """
    rows = 8
    row_zs = [
        WALL_BOTTOM + 0.042
        + row * (WALL_TOP - WALL_BOTTOM - 0.084) / (rows - 1)
        for row in range(rows)
    ]
    row_spacing = (WALL_TOP - WALL_BOTTOM - 0.084) / (rows - 1)
    bridge_gap = 0.010
    baseline = 0.015

    for face_axis, columns in (("Y", 11), ("X", 9)):
        for sign in (-1, 1):
            for row, row_z in enumerate(row_zs):
                for column in range(columns):
                    # Positive parity is the crossing where the horizontal
                    # course sits in front of the vertical stake.
                    if (row + column) % 2 != 0:
                        continue
                    for half_sign in (-1, 1):
                        sections = []
                        for sample in range(7):
                            t = sample / 6
                            smooth = t * t * (3.0 - 2.0 * t)
                            offset = (bridge_gap * 0.5
                                      + (WALL_HORIZONTAL_WIDTH * 0.5
                                         - bridge_gap * 0.5) * t)
                            z = row_z + half_sign * offset
                            local_row = row + (z - row_z) / row_spacing
                            crossing = math.cos(
                                math.pi * local_row + column * math.pi)

                            if face_axis == "Y":
                                span = width_at(z) - 0.08
                                along = (-span * 0.5
                                         + span * column / (columns - 1))
                                surface = depth_at(z) * 0.5
                            else:
                                span = depth_at(z) - 0.08
                                along = (-span * 0.5
                                         + span * column / (columns - 1))
                                surface = width_at(z) * 0.5

                            horizontal_front = (
                                surface + baseline
                                + WALL_CROSSING_DEPTH * crossing
                                + WOVEN_STRIP_THICKNESS * 0.5 + 0.0004)
                            vertical_center = (
                                surface + baseline
                                - WALL_CROSSING_DEPTH * crossing)
                            vertical_front = (
                                vertical_center
                                + WOVEN_STRIP_THICKNESS * 0.5)
                            front = (horizontal_front * (1.0 - smooth)
                                     + vertical_front * smooth)
                            thickness = (0.0035 * (1.0 - smooth)
                                         + WOVEN_STRIP_THICKNESS * smooth)
                            back = front - thickness
                            inner = sign * back
                            outer = sign * front

                            if face_axis == "Y":
                                sections.append([
                                    Vector((along - WALL_VERTICAL_WIDTH * 0.5,
                                            inner, z)),
                                    Vector((along + WALL_VERTICAL_WIDTH * 0.5,
                                            inner, z)),
                                    Vector((along + WALL_VERTICAL_WIDTH * 0.5,
                                            outer, z)),
                                    Vector((along - WALL_VERTICAL_WIDTH * 0.5,
                                            outer, z)),
                                ])
                            else:
                                sections.append([
                                    Vector((inner,
                                            along - WALL_VERTICAL_WIDTH * 0.5,
                                            z)),
                                    Vector((outer,
                                            along - WALL_VERTICAL_WIDTH * 0.5,
                                            z)),
                                    Vector((outer,
                                            along + WALL_VERTICAL_WIDTH * 0.5,
                                            z)),
                                    Vector((inner,
                                            along + WALL_VERTICAL_WIDTH * 0.5,
                                            z)),
                                ])
                        objects.append(add_closed_ribbon_mesh(
                            f"{'FrontBack' if face_axis == 'Y' else 'Side'}VerticalContinuity_{sign}_{row}_{column}_{half_sign}",
                            sections, vertical_mat, 0.0015))


def add_outer_vertical_under_seams(objects, vertical_mat):
    """Mark the hidden continuation of outer stakes without opening gaps."""
    rows = 8
    row_zs = [
        WALL_BOTTOM + 0.042
        + row * (WALL_TOP - WALL_BOTTOM - 0.084) / (rows - 1)
        for row in range(rows)
    ]
    baseline = 0.015
    seam_width = 0.014

    for face_axis, columns in (("Y", 11), ("X", 9)):
        for sign in (-1, 1):
            verts = []
            faces = []
            for row, row_z in enumerate(row_zs):
                for column in range(columns):
                    if (row + column) % 2 != 0:
                        continue
                    z0 = row_z - WALL_HORIZONTAL_WIDTH * 0.5
                    z1 = row_z + WALL_HORIZONTAL_WIDTH * 0.5
                    section = []
                    for z in (z0, z1):
                        if face_axis == "Y":
                            span = width_at(z) - 0.08
                            along = (-span * 0.5
                                     + span * column / (columns - 1))
                            surface = depth_at(z) * 0.5
                        else:
                            span = depth_at(z) - 0.08
                            along = (-span * 0.5
                                     + span * column / (columns - 1))
                            surface = width_at(z) * 0.5
                        radial = (surface + baseline + WALL_CROSSING_DEPTH
                                  + WOVEN_STRIP_THICKNESS * 0.5 + 0.0005)
                        if face_axis == "Y":
                            section.extend([
                                Vector((along - seam_width * 0.5,
                                        sign * radial, z)),
                                Vector((along + seam_width * 0.5,
                                        sign * radial, z)),
                            ])
                        else:
                            section.extend([
                                Vector((sign * radial,
                                        along - seam_width * 0.5, z)),
                                Vector((sign * radial,
                                        along + seam_width * 0.5, z)),
                            ])
                    base = len(verts)
                    verts.extend(section)
                    faces.append((base, base + 1, base + 3, base + 2))
            objects.append(mesh_object(
                f"{'FrontBack' if face_axis == 'Y' else 'Side'}VerticalUnderSeams_{sign}",
                verts, faces, vertical_mat, 0.0008))


def add_corner_shaping(objects, mat):
    for sx in (-1, 1):
        for sy in (-1, 1):
            points = []
            for step in range(5):
                z = WALL_BOTTOM + (WALL_TOP - WALL_BOTTOM) * step / 4
                points.append(Vector((sx * width_at(z) * 0.5, sy * depth_at(z) * 0.5, z)))
            objects.append(add_curve(f"RoundedCornerSupport_{sx}_{sy}", points, 0.022, mat, False, 1))


def rounded_rect_coarse(width, depth, radius, z, samples_per_corner=12):
    points = []
    centers = [
        (width * 0.5 - radius, depth * 0.5 - radius, 0),
        (-width * 0.5 + radius, depth * 0.5 - radius, 90),
        (-width * 0.5 + radius, -depth * 0.5 + radius, 180),
        (width * 0.5 - radius, -depth * 0.5 + radius, 270),
    ]
    for cx, cy, start in centers:
        for i in range(samples_per_corner):
            angle = math.radians(start + i * 90 / samples_per_corner)
            points.append(Vector((cx + radius * math.cos(angle), cy + radius * math.sin(angle), z)))
    return points


def resample_closed(points, count):
    lengths = [(points[(i + 1) % len(points)] - point).length for i, point in enumerate(points)]
    total = sum(lengths)
    result = []
    segment = 0
    start_distance = 0.0
    for sample in range(count):
        target = total * sample / count
        while start_distance + lengths[segment] < target:
            start_distance += lengths[segment]
            segment += 1
        alpha = (target - start_distance) / lengths[segment]
        result.append(points[segment].lerp(points[(segment + 1) % len(points)], alpha))
    return result


def add_thick_twisted_rim(objects, core_mat, wrap_mat):
    base = resample_closed(rounded_rect_coarse(
        TARGET_W - 0.17, TARGET_D - 0.17, 0.24, 0.824), 160)
    rim_core = add_curve("ContinuousSoftTopRim", base, 0.049, core_mat, True, 2)
    # Preserve the rounded rectangle footprint while flattening only the
    # vertical cross-section so the rim no longer reads as an inflated tube.
    rim_vertical_scale = 0.84
    rim_core.scale.z = rim_vertical_scale
    rim_core.location.z = 0.824 * (1.0 - rim_vertical_scale)
    objects.append(rim_core)
    n = len(base)
    for strand in range(2):
        wrapped = []
        for i, point in enumerate(base):
            tangent = (base[(i + 1) % n] - base[(i - 1) % n]).normalized()
            outward = Vector((tangent.y, -tangent.x, 0)).normalized()
            angle = strand * math.pi + math.tau * 22 * i / n
            wrapped.append(point + outward * (0.047 * math.cos(angle))
                           + Vector((0, 0, 0.037 * math.sin(angle))))
        objects.append(add_curve(
            f"RimDiagonalTwist_{strand+1}", wrapped, 0.0065,
            wrap_mat, True, 1))


def add_bottom(objects, mat):
    objects.append(add_box(
        "CleanBottomPanel", (0, 0, 0.060),
        (LOWER_W - 0.06, LOWER_D - 0.06, 0.035), (0, 0, 0), mat, 0.012))


def add_woven_bottom(objects, horizontal_mats, vertical_mat):
    """Build the floor from the same closed over-under ribbons as the walls."""
    span_x = LOWER_W - 0.08
    span_y = LOWER_D - 0.08
    wall_cell = (WALL_TOP - WALL_BOTTOM - 0.084) / 7
    # Match the wall language: sparse continuous vertical stakes crossed by
    # tightly packed dominant horizontal courses.
    x_crossing_count = 11
    y_crossing_count = round(span_y / wall_cell) + 1
    # Meet the lower wall weave without hanging below it as a scalloped edge.
    base_z = 0.095
    crossing_depth = WALL_CROSSING_DEPTH

    # Ribbons running left-to-right.
    for row in range(y_crossing_count):
        y = -span_y * 0.5 + span_y * row / (y_crossing_count - 1)
        samples = (x_crossing_count - 1) * 8 + 1
        sections = []
        for sample in range(samples):
            u = sample / (samples - 1)
            x = -span_x * 0.5 + span_x * u
            crossing = math.cos(
                math.pi * (x_crossing_count - 1) * u + row * math.pi)
            center = base_z + crossing_depth * crossing
            sections.append([
                Vector((x, y - WOVEN_STRIP_WIDTH * 0.5,
                        center - WOVEN_STRIP_THICKNESS * 0.5)),
                Vector((x, y + WOVEN_STRIP_WIDTH * 0.5,
                        center - WOVEN_STRIP_THICKNESS * 0.5)),
                Vector((x, y + WOVEN_STRIP_WIDTH * 0.5,
                        center + WOVEN_STRIP_THICKNESS * 0.5)),
                Vector((x, y - WOVEN_STRIP_WIDTH * 0.5,
                        center + WOVEN_STRIP_THICKNESS * 0.5)),
            ])
        objects.append(add_closed_ribbon_mesh(
            f"BottomHorizontalRibbon_{row}", sections,
            horizontal_mats[row % len(horizontal_mats)], 0.0045))

    # Ribbons running front-to-back, using the inverse depth at every crossing.
    for column in range(x_crossing_count):
        x = -span_x * 0.5 + span_x * column / (x_crossing_count - 1)
        samples = (y_crossing_count - 1) * 8 + 1
        sections = []
        for sample in range(samples):
            t = sample / (samples - 1)
            y = -span_y * 0.5 + span_y * t
            crossing = math.cos(
                math.pi * (y_crossing_count - 1) * t + column * math.pi)
            center = base_z - crossing_depth * crossing
            sections.append([
                Vector((x - WALL_VERTICAL_WIDTH * 0.5, y,
                        center - WOVEN_STRIP_THICKNESS * 0.5)),
                Vector((x + WALL_VERTICAL_WIDTH * 0.5, y,
                        center - WOVEN_STRIP_THICKNESS * 0.5)),
                Vector((x + WALL_VERTICAL_WIDTH * 0.5, y,
                        center + WOVEN_STRIP_THICKNESS * 0.5)),
                Vector((x - WALL_VERTICAL_WIDTH * 0.5, y,
                        center + WOVEN_STRIP_THICKNESS * 0.5)),
            ])
        objects.append(add_closed_ribbon_mesh(
            f"BottomVerticalRibbon_{column}", sections, vertical_mat, 0.0045))


def convert_to_mesh(objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.convert(target="MESH")
    return [obj for obj in bpy.context.selected_objects if obj.type == "MESH"]


def object_bounds(objects):
    corners = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    return min(p.x for p in corners), max(p.x for p in corners), min(p.y for p in corners), max(p.y for p in corners), min(p.z for p in corners), max(p.z for p in corners)


def normalize(objects):
    for _ in range(2):
        min_x, max_x, min_y, max_y, min_z, max_z = object_bounds(objects)
        cx, cy = (min_x + max_x) * 0.5, (min_y + max_y) * 0.5
        sx, sy, sz = TARGET_W / (max_x - min_x), TARGET_D / (max_y - min_y), TARGET_H / (max_z - min_z)
        for obj in objects:
            obj.location.x = (obj.location.x - cx) * sx
            obj.location.y = (obj.location.y - cy) * sy
            obj.location.z = (obj.location.z - min_z) * sz
            obj.scale.x *= sx
            obj.scale.y *= sy
            obj.scale.z *= sz
        bpy.context.view_layer.update()


def report_stats(objects):
    min_x, max_x, min_y, max_y, min_z, max_z = object_bounds(objects)
    triangles = 0
    for obj in objects:
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)
    print(f"Verified basket bounds: {max_x-min_x:.4f} x {max_y-min_y:.4f} x {max_z-min_z:.4f} studs")
    print(f"Editable visible object count: {len(objects)}")
    print(f"Visual triangle count: {triangles}")


def duplicate_and_join(objects):
    bpy.ops.object.select_all(action="DESELECT")
    copies = []
    for obj in objects:
        copy = obj.copy()
        copy.data = obj.data.copy()
        bpy.context.collection.objects.link(copy)
        copy.select_set(True)
        copies.append(copy)
    bpy.context.view_layer.objects.active = copies[0]
    # Export copies may include editable prototype Curves. Convert only the
    # copies so the .blend source retains its editable Curve objects.
    bpy.ops.object.convert(target="MESH")
    copies = [obj for obj in bpy.context.selected_objects if obj.type == "MESH"]
    bpy.context.view_layer.objects.active = copies[0]
    bpy.ops.object.join()
    joined = bpy.context.object
    joined.name = "LowWideWovenBasket"
    tri = joined.modifiers.new("RobloxTriangulation", "TRIANGULATE")
    bpy.ops.object.modifier_apply(modifier=tri.name)
    return joined


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def render_preview(clay_mat):
    ground_mat = bpy.data.materials.new("PreviewGround")
    ground_mat.diffuse_color = (0.055, 0.075, 0.10, 1)
    bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, -0.006))
    bpy.context.object.data.materials.append(ground_mat)
    bpy.ops.object.camera_add(location=(0.0, -5.80, 1.02))
    camera = bpy.context.object
    camera.data.lens = 74
    look_at(camera, (0, 0, 0.41))
    bpy.context.scene.camera = camera
    bpy.ops.object.light_add(type="AREA", location=(-2.8, -3.3, 4.2))
    key = bpy.context.object
    key.data.energy = 620
    key.data.size = 4.0
    look_at(key, (0, 0, 0.4))
    bpy.ops.object.light_add(type="AREA", location=(3.2, 1.5, 2.3))
    fill = bpy.context.object
    fill.data.energy = 330
    fill.data.size = 3.0
    look_at(fill, (0, 0, 0.4))
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 760
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = PREVIEW_PATH
    scene.world.color = (0.018, 0.027, 0.043)
    bpy.ops.render.render(write_still=True)

    # Required comparison A: near-front single-color clay view. The stored
    # camera and lighting are not changed.
    scene.view_layers[0].material_override = clay_mat
    scene.render.filepath = FRONT_COMPARE_PATH
    bpy.ops.render.render(write_still=True)

    # Required comparison B: temporary angled close-up. Remove this camera
    # after rendering so the existing camera remains untouched in the file.
    angle_camera_data = camera.data.copy()
    angle_camera = bpy.data.objects.new("TEMP_FrontWeaveAngleCamera", angle_camera_data)
    bpy.context.collection.objects.link(angle_camera)
    angle_camera.location = (2.75, -4.15, 1.18)
    angle_camera.data.lens = 78
    look_at(angle_camera, (0.25, -0.88, 0.43))
    scene.camera = angle_camera
    scene.render.filepath = ANGLE_COMPARE_PATH
    bpy.ops.render.render(write_still=True)

    # Temporary top-down check that the interior is the reverse face of the
    # actual weave and that the floor is woven rather than a flat panel.
    angle_camera.location = (0.0, -0.28, 1.72)
    angle_camera.data.lens = 62
    look_at(angle_camera, (0.0, 0.0, 0.20))
    scene.render.filepath = INTERIOR_PREVIEW_PATH
    bpy.ops.render.render(write_still=True)

    angle_camera.location = (0.0, 0.30, 0.58)
    angle_camera.data.lens = 56
    look_at(angle_camera, (0.0, -1.02, 0.43))
    scene.render.filepath = INTERIOR_WALL_PREVIEW_PATH
    bpy.ops.render.render(write_still=True)
    scene.camera = camera
    scene.view_layers[0].material_override = None
    bpy.data.objects.remove(angle_camera, do_unlink=True)
    bpy.data.cameras.remove(angle_camera_data)
    scene.render.filepath = PREVIEW_PATH


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    reset_scene()
    panel_mat = wicker_material("Dense Wicker Panel", (0.175, 0.045, 0.006), 0.16)
    detail_mat = wicker_material(
        "Vertical Woven Ribbon", (0.245, 0.075, 0.011), 0.22, "Z")
    front_band_mats = [
        wicker_material("Front Band Honey", (0.245, 0.075, 0.011), 0.22, "X"),
        wicker_material("Front Band Amber", (0.295, 0.105, 0.020), 0.22, "X"),
        wicker_material("Front Band Light", (0.345, 0.145, 0.032), 0.20, "X"),
    ]
    side_band_mats = [
        wicker_material("Side Band Honey", (0.245, 0.075, 0.011), 0.22, "Y"),
        wicker_material("Side Band Amber", (0.295, 0.105, 0.020), 0.22, "Y"),
        wicker_material("Side Band Light", (0.345, 0.145, 0.032), 0.20, "Y"),
    ]
    overpass_mat = wicker_material("Woven Vertical Overpass", (0.155, 0.035, 0.004), 0.17)
    corner_mat = wicker_material("Rounded Corner Wicker", (0.20, 0.060, 0.009), 0.14)
    rim_mat = wicker_material("Thick Soft Rim", (0.285, 0.095, 0.015), 0.20)
    wrap_mat = wicker_material("Rim Diagonal Grain", (0.135, 0.030, 0.003), 0.14)
    prototype_mat = wicker_material(
        "Front Prototype Wicker", (0.285, 0.100, 0.018), 0.14)
    clay_mat = bpy.data.materials.new("Front Weave Clay Preview")
    clay_mat.diffuse_color = (0.30, 0.105, 0.020, 1.0)
    clay_mat.use_nodes = True
    clay_bsdf = clay_mat.node_tree.nodes.get("Principled BSDF")
    clay_bsdf.inputs["Base Color"].default_value = (0.30, 0.105, 0.020, 1.0)
    clay_bsdf.inputs["Roughness"].default_value = 0.76

    basket = []
    add_woven_bottom(basket, front_band_mats, detail_mat)
    add_solid_wall_panels(basket, panel_mat)
    add_true_layered_weave(basket, front_band_mats, side_band_mats, detail_mat)
    add_corner_shaping(basket, corner_mat)
    add_thick_twisted_rim(basket, rim_mat, wrap_mat)
    basket = convert_to_mesh(basket)

    # Keep the same authored layered weave on all four faces.  The separate
    # front Curve prototype is intentionally no longer instantiated.
    bpy.context.view_layer.update()
    normalize(basket)
    report_stats(basket)
    for obj in basket:
        obj["CollisionIntent"] = "VisualOnly"
        obj["RobloxStudScale"] = 1.0

    render_preview(clay_mat)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    export_mesh = duplicate_and_join(basket)
    export_mesh["TargetDimensionsStuds"] = "2.55 x 2.20 x 0.90"
    bpy.ops.object.select_all(action="DESELECT")
    export_mesh.select_set(True)
    bpy.context.view_layer.objects.active = export_mesh
    bpy.ops.export_scene.fbx(filepath=FBX_PATH, use_selection=True, apply_unit_scale=True, apply_scale_options="FBX_SCALE_UNITS", axis_forward="-Z", axis_up="Y", use_mesh_modifiers=True, mesh_smooth_type="FACE", add_leaf_bones=False, bake_anim=False)
    bpy.ops.export_scene.gltf(filepath=GLB_PATH, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    bpy.data.objects.remove(export_mesh, do_unlink=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print(f"Created {BLEND_PATH}")
    print(f"Created {FBX_PATH}")
    print(f"Created {GLB_PATH}")
    print(f"Created {PREVIEW_PATH}")
    print(f"Created {FRONT_COMPARE_PATH}")
    print(f"Created {ANGLE_COMPARE_PATH}")
    print(f"Created {INTERIOR_PREVIEW_PATH}")
    print(f"Created {INTERIOR_WALL_PREVIEW_PATH}")
    print("Front wall restored to the same layered weave as the other three walls")
    print(
        f"Restored ribbon widths: horizontal {WALL_HORIZONTAL_WIDTH:.3f}, "
        f"vertical {WALL_VERTICAL_WIDTH:.3f} studs")
    print("Preserved inner wall panels; bottom uses two-sided woven ribbons only")


if __name__ == "__main__":
    main()
