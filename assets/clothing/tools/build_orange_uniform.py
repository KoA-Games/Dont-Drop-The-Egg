from __future__ import annotations

import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance


ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT / "reference" / "templates"
FINAL = ROOT / "final"
QA = ROOT / "qa"

CANVAS_SIZE = (585, 559)
ORANGE = (234, 92, 22, 255)
ORANGE_LIGHT = (246, 112, 30, 255)
ORANGE_DARK = (188, 57, 12, 255)
NAVY = (22, 39, 70, 255)
NAVY_LIGHT = (31, 54, 92, 255)
NAVY_DARK = (11, 22, 43, 255)
SOLE = (224, 216, 194, 255)
SOLE_DARK = (164, 157, 142, 255)
UV_BLEED_PIXELS = 3

# Coordinates follow Roblox's official 585x559 R15 classic-clothing templates.
TORSO = {
    "up": (231, 8, 358, 72),
    "right": (165, 74, 228, 201),
    "front": (231, 74, 358, 201),
    "left": (361, 74, 424, 201),
    "back": (427, 74, 554, 201),
    "down": (231, 203, 358, 266),
}

RIGHT_LIMB = {
    "up": (217, 290, 280, 353),
    "left": (19, 355, 82, 482),
    "back": (85, 355, 148, 482),
    "right": (151, 355, 214, 482),
    "front": (217, 355, 280, 482),
    "down": (217, 484, 280, 548),
}

LEFT_LIMB = {
    "up": (308, 290, 371, 353),
    "front": (308, 355, 371, 482),
    "left": (374, 355, 437, 482),
    "back": (440, 355, 503, 482),
    "right": (506, 355, 569, 482),
    "down": (308, 484, 371, 548),
}


def dimensions(box: tuple[int, int, int, int]) -> tuple[int, int]:
    return box[2] - box[0] + 1, box[3] - box[1] + 1


def fabric_panel(
    size: tuple[int, int],
    base: tuple[int, int, int, int],
    seed: int,
) -> Image.Image:
    """Make restrained cheap-polyester variation without breaking UV seams."""
    width, height = size
    randomizer = random.Random(seed)
    panel = Image.new("RGBA", size, base)
    pixels = panel.load()
    for y in range(height):
        vertical = int(4 * (0.5 - y / max(height - 1, 1)))
        for x in range(width):
            noise = randomizer.choice((-2, -1, 0, 0, 0, 1, 2))
            highlight = 2 if (x + y * 2) % 29 == 0 else 0
            pixels[x, y] = (
                max(0, min(255, base[0] + vertical + noise + highlight)),
                max(0, min(255, base[1] + vertical + noise + highlight)),
                max(0, min(255, base[2] + vertical + noise + highlight)),
                base[3],
            )
    return panel


def paste_fabric(
    atlas: Image.Image,
    box: tuple[int, int, int, int],
    color: tuple[int, int, int, int],
    seed: int,
) -> None:
    atlas.alpha_composite(fabric_panel(dimensions(box), color, seed), (box[0], box[1]))


def paint_uv_bleed(
    atlas: Image.Image,
    boxes: list[tuple[int, int, int, int]],
    color: tuple[int, int, int, int],
    pixels: int = UV_BLEED_PIXELS,
) -> None:
    """Fill beyond UV island edges so filtered textures never sample transparency."""
    draw = ImageDraw.Draw(atlas)
    canvas_width, canvas_height = atlas.size
    for x0, y0, x1, y1 in boxes:
        draw.rectangle(
            (
                max(0, x0 - pixels),
                max(0, y0 - pixels),
                min(canvas_width - 1, x1 + pixels),
                min(canvas_height - 1, y1 + pixels),
            ),
            fill=color,
        )


def local_draw(atlas: Image.Image, box: tuple[int, int, int, int]) -> ImageDraw.ImageDraw:
    panel = atlas.crop((box[0], box[1], box[2] + 1, box[3] + 1))
    return ImageDraw.Draw(panel), panel


def commit_panel(
    atlas: Image.Image,
    box: tuple[int, int, int, int],
    panel: Image.Image,
) -> None:
    atlas.alpha_composite(panel, (box[0], box[1]))


def ribbing(draw: ImageDraw.ImageDraw, y0: int, y1: int, width: int) -> None:
    draw.rectangle((0, y0, width - 1, y1), fill=NAVY)
    for x in range(2, width, 6):
        draw.line((x, y0 + 1, x, y1 - 1), fill=NAVY_LIGHT, width=1)
    draw.line((0, y0, width - 1, y0), fill=NAVY_DARK, width=1)


def style_torso_face(
    atlas: Image.Image,
    box: tuple[int, int, int, int],
    face: str,
) -> None:
    width, height = dimensions(box)
    panel = atlas.crop((box[0], box[1], box[2] + 1, box[3] + 1))
    draw = ImageDraw.Draw(panel)

    if face == "front":
        draw.polygon(((0, 0), (38, 0), (27, 25), (0, 31)), fill=NAVY)
        draw.polygon(((width - 1, 0), (width - 39, 0), (width - 28, 25), (width - 1, 31)), fill=NAVY)
        draw.rectangle((56, 0, 71, 11), fill=NAVY)
        draw.rectangle((62, 0, 65, height - 1), fill=NAVY_DARK)
        draw.line((66, 0, 66, height - 1), fill=NAVY_LIGHT, width=1)
        draw.rectangle((62, 9, 68, 14), fill=(118, 124, 128, 255))
        draw.line((22, 78, 15, 105), fill=NAVY, width=5)
        draw.line((width - 23, 78, width - 16, 105), fill=NAVY, width=5)
    elif face == "back":
        draw.polygon(((0, 0), (width - 1, 0), (width - 1, 25), (91, 22), (64, 17), (36, 22), (0, 25)), fill=NAVY)
        draw.line((0, 26, width - 1, 26), fill=NAVY_DARK, width=1)
    else:
        # These are the torso's armpit-facing side panels. Keep them solid and
        # opaque so raised arms reveal orange fabric instead of a dark wedge.
        draw.rectangle((0, 0, width - 1, height - 1), fill=ORANGE)

    ribbing(draw, height - 13, height - 1, width)
    if face in ("front", "back"):
        draw.line((0, 0, 0, height - 1), fill=ORANGE_DARK, width=1)
        draw.line((width - 1, 0, width - 1, height - 1), fill=ORANGE_DARK, width=1)
    commit_panel(atlas, box, panel)


def style_sleeve_face(
    atlas: Image.Image,
    box: tuple[int, int, int, int],
    navy_outer_shoulder: bool,
) -> None:
    width, height = dimensions(box)
    panel = atlas.crop((box[0], box[1], box[2] + 1, box[3] + 1))
    draw = ImageDraw.Draw(panel)
    if navy_outer_shoulder:
        draw.rectangle((0, 0, width - 1, 24), fill=NAVY)
        draw.line((0, 25, width - 1, 25), fill=NAVY_DARK, width=1)
    else:
        # Front, back, and inner upper-arm faces are seam-safe solid orange.
        # This prevents the navy shoulder treatment from reading as an open
        # armpit when the arm rotates overhead.
        draw.rectangle((0, 0, width - 1, 31), fill=ORANGE)
    ribbing(draw, height - 14, height - 1, width)
    if navy_outer_shoulder:
        draw.line((0, 0, 0, height - 1), fill=ORANGE_DARK, width=1)
        draw.line((width - 1, 0, width - 1, height - 1), fill=ORANGE_DARK, width=1)
    commit_panel(atlas, box, panel)


def build_shirt() -> Image.Image:
    atlas = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    shirt_boxes = list(TORSO.values()) + list(RIGHT_LIMB.values()) + list(LEFT_LIMB.values())
    paint_uv_bleed(atlas, shirt_boxes, ORANGE)
    seed = 100
    for box in TORSO.values():
        paste_fabric(atlas, box, ORANGE, seed)
        seed += 1
    for limb in (RIGHT_LIMB, LEFT_LIMB):
        for box in limb.values():
            paste_fabric(atlas, box, ORANGE, seed)
            seed += 1

    for face in ("front", "back", "right", "left"):
        style_torso_face(atlas, TORSO[face], face)

    for face in ("left", "back", "right", "front"):
        style_sleeve_face(
            atlas,
            RIGHT_LIMB[face],
            navy_outer_shoulder=face == "right",
        )
        style_sleeve_face(
            atlas,
            LEFT_LIMB[face],
            navy_outer_shoulder=face == "left",
        )

    paste_fabric(atlas, TORSO["up"], NAVY, seed)
    seed += 1
    # Arm top caps are hidden shoulder seams; solid orange gives continuous
    # coverage as the arms rotate from resting to overhead.
    for box in (RIGHT_LIMB["up"], LEFT_LIMB["up"]):
        paste_fabric(atlas, box, ORANGE, seed)
        seed += 1
    for box in (TORSO["down"], RIGHT_LIMB["down"], LEFT_LIMB["down"]):
        paste_fabric(atlas, box, NAVY_DARK, seed)
        seed += 1
    return atlas


def validate_shirt_uv_coverage(shirt: Image.Image) -> None:
    alpha = shirt.getchannel("A")
    all_boxes = list(TORSO.values()) + list(RIGHT_LIMB.values()) + list(LEFT_LIMB.values())
    for index, (x0, y0, x1, y1) in enumerate(all_boxes):
        mapped_alpha = alpha.crop((x0, y0, x1 + 1, y1 + 1))
        if mapped_alpha.getextrema() != (255, 255):
            raise ValueError(f"shirt UV panel {index} contains transparent pixels")

        bleed_alpha = alpha.crop(
            (
                max(0, x0 - UV_BLEED_PIXELS),
                max(0, y0 - UV_BLEED_PIXELS),
                min(CANVAS_SIZE[0], x1 + UV_BLEED_PIXELS + 1),
                min(CANVAS_SIZE[1], y1 + UV_BLEED_PIXELS + 1),
            )
        )
        if bleed_alpha.getextrema() != (255, 255):
            raise ValueError(f"shirt UV panel {index} has incomplete edge bleed")


def style_pant_face(
    atlas: Image.Image,
    box: tuple[int, int, int, int],
    outer_side: bool,
    front: bool,
) -> None:
    width, height = dimensions(box)
    panel = atlas.crop((box[0], box[1], box[2] + 1, box[3] + 1))
    draw = ImageDraw.Draw(panel)

    ribbing(draw, 0, 10, width)
    if outer_side:
        center = width // 2
        draw.rectangle((center - 5, 11, center + 5, height - 30), fill=NAVY)
        draw.line((center - 6, 11, center - 6, height - 30), fill=NAVY_DARK, width=1)
        draw.line((center + 6, 11, center + 6, height - 30), fill=ORANGE_LIGHT, width=1)
    elif front:
        draw.line((width // 2, 14, width // 2, height - 31), fill=ORANGE_DARK, width=1)

    shoe_top = height - 29
    draw.polygon(((0, shoe_top + 5), (width // 3, shoe_top), (width - 1, shoe_top + 3), (width - 1, height - 1), (0, height - 1)), fill=NAVY)
    draw.line((0, shoe_top + 4, width - 1, shoe_top + 2), fill=NAVY_LIGHT, width=2)
    draw.rectangle((0, height - 7, width - 1, height - 1), fill=SOLE)
    draw.line((0, height - 8, width - 1, height - 8), fill=SOLE_DARK, width=1)
    draw.line((0, 0, 0, height - 1), fill=ORANGE_DARK, width=1)
    draw.line((width - 1, 0, width - 1, height - 1), fill=ORANGE_DARK, width=1)
    commit_panel(atlas, box, panel)


def style_pants_waist_face(
    atlas: Image.Image,
    box: tuple[int, int, int, int],
    front: bool,
) -> None:
    width, height = dimensions(box)
    panel = atlas.crop((box[0], box[1], box[2] + 1, box[3] + 1))
    draw = ImageDraw.Draw(panel)
    ribbing(draw, 0, 14, width)
    if front:
        draw.line((width // 2, 15, width // 2, height - 1), fill=ORANGE_DARK, width=1)
        draw.arc((width // 2 - 12, 15, width // 2 + 12, 35), 0, 180, fill=ORANGE_DARK, width=1)
    draw.line((0, 0, 0, height - 1), fill=ORANGE_DARK, width=1)
    draw.line((width - 1, 0, width - 1, height - 1), fill=ORANGE_DARK, width=1)
    commit_panel(atlas, box, panel)


def build_pants() -> Image.Image:
    atlas = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    seed = 300
    for box in TORSO.values():
        paste_fabric(atlas, box, ORANGE, seed)
        seed += 1
    for limb in (RIGHT_LIMB, LEFT_LIMB):
        for box in limb.values():
            paste_fabric(atlas, box, ORANGE, seed)
            seed += 1

    for face in ("front", "back", "right", "left"):
        style_pants_waist_face(atlas, TORSO[face], front=face == "front")
    paste_fabric(atlas, TORSO["up"], NAVY, seed)
    seed += 1
    paste_fabric(atlas, TORSO["down"], ORANGE_DARK, seed)
    seed += 1

    # Outward sides are R on the right leg and L on the left leg.
    for face in ("left", "back", "right", "front"):
        style_pant_face(
            atlas,
            RIGHT_LIMB[face],
            outer_side=face == "right",
            front=face == "front",
        )
        style_pant_face(
            atlas,
            LEFT_LIMB[face],
            outer_side=face == "left",
            front=face == "front",
        )

    for box in (RIGHT_LIMB["up"], LEFT_LIMB["up"]):
        paste_fabric(atlas, box, NAVY, seed)
        seed += 1
    for box in (RIGHT_LIMB["down"], LEFT_LIMB["down"]):
        paste_fabric(atlas, box, SOLE, seed)
        seed += 1
    return atlas


def make_qa_overlay(final: Image.Image, template_path: Path) -> Image.Image:
    template = Image.open(template_path).convert("RGBA")
    muted = ImageEnhance.Brightness(template).enhance(0.72)
    result = muted.copy()
    translucent = final.copy()
    translucent.putalpha(final.getchannel("A").point(lambda alpha: int(alpha * 0.78)))
    result.alpha_composite(translucent)
    return result


def main() -> None:
    FINAL.mkdir(parents=True, exist_ok=True)
    QA.mkdir(parents=True, exist_ok=True)

    shirt = build_shirt()
    pants = build_pants()
    validate_shirt_uv_coverage(shirt)
    shirt_path = FINAL / "orange_navy_training_uniform_shirt_v2_seam_fixed.png"
    pants_path = FINAL / "orange_navy_training_uniform_pants_v1.png"
    shirt.save(shirt_path)
    pants.save(pants_path)

    make_qa_overlay(shirt, REFERENCE / "Template-Shirts-R15.png").save(
        QA / "orange_navy_training_uniform_shirt_v2_seam_fixed_uv_qa.png"
    )
    make_qa_overlay(pants, REFERENCE / "Template-Pants-R15.png").save(
        QA / "orange_navy_training_uniform_pants_v1_uv_qa.png"
    )

    print(shirt_path)
    print(pants_path)


if __name__ == "__main__":
    main()
