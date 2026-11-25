#!/usr/bin/env python3
"""Recolor the Roblox Business Coat ColorMap without changing its UV layout."""

import random
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "source" / "business_coat_striped_gray_colormap_7478204422.png"
OUTPUT = ROOT / "final" / "egg_tracksuit_v3.png"
QA = ROOT / "qa" / "business_coat_orange_navy_tracksuit_colormap_v3_detailed_comparison.png"

ORANGE = (239, 83, 12)
ORANGE_LIGHT = (255, 112, 30)
ORANGE_DARK = (173, 48, 7)
NAVY = (10, 34, 78)
NAVY_LIGHT = (27, 57, 105)
NAVY_DARK = (4, 17, 43)


def fabric_color(
	color: tuple[int, int, int],
	x: int,
	y: int,
	randomizer: random.Random,
) -> tuple[int, int, int]:
	"""Generate subtle polyester texture without importing gray pinstripes."""
	noise = randomizer.choice((-3, -2, -1, 0, 0, 0, 1, 2, 3))
	vertical = round(3 * (0.5 - y / 511.0))
	thread = 2 if (x + y * 2) % 31 == 0 else 0
	adjustment = noise + vertical + thread
	return tuple(min(255, max(0, channel + adjustment)) for channel in color)


def outlined_line(
	draw: ImageDraw.ImageDraw,
	points: list[tuple[int, int]],
	dark: tuple[int, int, int],
	light: tuple[int, int, int],
	width: int,
) -> None:
	draw.line(points, fill=dark, width=width)
	draw.line([(x + 1, y) for x, y in points], fill=light, width=max(1, width // 3))


def add_ribbing(
	draw: ImageDraw.ImageDraw,
	box: tuple[int, int, int, int],
	vertical: bool,
) -> None:
	x0, y0, x1, y1 = box
	draw.rectangle(box, fill=NAVY)
	if vertical:
		for x in range(x0 + 2, x1, 6):
			draw.line((x, y0 + 1, x, y1 - 1), fill=NAVY_LIGHT, width=1)
	else:
		for y in range(y0 + 2, y1, 6):
			draw.line((x0 + 1, y, x1 - 1, y), fill=NAVY_LIGHT, width=1)
	draw.rectangle(box, outline=NAVY_DARK, width=2)


def build() -> None:
	source = Image.open(SOURCE).convert("RGB")
	if source.size != (512, 512):
		raise ValueError(f"unexpected ColorMap size: {source.size}")

	# The layered jacket uses a different UV layout from a classic shirt. These
	# broad regions place the tracksuit design on the coat's sleeve, front, back,
	# collar/lapel and hem islands without moving a single UV coordinate.
	navy_mask = Image.new("L", source.size, 0)
	mask_draw = ImageDraw.Draw(navy_mask)

	# Sleeve islands run horizontally across the upper portion. Dark center
	# sections become shoulder panels; the outer ends become ribbed cuffs.
	mask_draw.rectangle((0, 0, 48, 178), fill=255)
	mask_draw.rectangle((190, 0, 322, 178), fill=255)
	mask_draw.rectangle((464, 0, 511, 178), fill=255)

	# Front and back shoulder yokes. Their lower edges dip slightly at the center,
	# matching the V-shaped navy panels on the classic tracksuit reference.
	mask_draw.polygon(
		[(0, 177), (220, 177), (220, 222), (169, 244), (110, 226), (51, 244), (0, 222)],
		fill=255,
	)
	mask_draw.polygon(
		[(300, 177), (511, 177), (511, 222), (464, 244), (406, 226), (348, 244), (300, 222)],
		fill=255,
	)

	# Collar and lapel islands sit in the center of the map. Making these navy
	# visually hides the business pinstripe identity and reads as a sport collar.
	mask_draw.rectangle((216, 0, 296, 160), fill=255)
	mask_draw.ellipse((207, 135, 311, 282), fill=255)

	# Ribbed waist band on the front and back coat panels. Fine rib lines are
	# drawn after the fabric fill so they stay crisp.
	mask_draw.rectangle((0, 474, 220, 511), fill=255)
	mask_draw.rectangle((300, 474, 511, 511), fill=255)

	mask_pixels = navy_mask.load()
	result = Image.new("RGB", source.size)
	result_pixels = result.load()
	randomizer = random.Random(8516648620)

	navy_pixels = 0
	for y in range(source.height):
		for x in range(source.width):
			if mask_pixels[x, y] > 0:
				navy_pixels += 1
				result_pixels[x, y] = fabric_color(NAVY, x, y, randomizer)
			else:
				result_pixels[x, y] = fabric_color(ORANGE, x, y, randomizer)

	# Rebuild the reference tracksuit details on the layered-jacket UV.
	detail = ImageDraw.Draw(result)

	# Shoulder-yoke seams: dark stitch channel plus a narrow highlight.
	front_yoke = [(0, 222), (51, 244), (110, 226), (169, 244), (220, 222)]
	back_yoke = [(300, 222), (348, 244), (406, 226), (464, 244), (511, 222)]
	outlined_line(detail, front_yoke, NAVY_DARK, NAVY_LIGHT, 4)
	outlined_line(detail, back_yoke, NAVY_DARK, NAVY_LIGHT, 4)

	# Sport zipper and twin slanted pocket zips on the front coat island.
	detail.rectangle((106, 246, 114, 474), fill=NAVY_DARK)
	detail.line((115, 246, 115, 474), fill=NAVY_LIGHT, width=2)
	detail.rectangle((104, 244, 117, 253), fill=(124, 133, 139))
	outlined_line(detail, [(50, 349), (63, 414)], NAVY_DARK, NAVY_LIGHT, 7)
	outlined_line(detail, [(166, 349), (153, 414)], NAVY_DARK, NAVY_LIGHT, 7)

	# Ribbed cuffs at the sleeve ends and ribbed waist bands.
	add_ribbing(detail, (0, 0, 48, 178), vertical=False)
	add_ribbing(detail, (464, 0, 511, 178), vertical=False)
	add_ribbing(detail, (0, 474, 220, 511), vertical=True)
	add_ribbing(detail, (300, 474, 511, 511), vertical=True)

	# Tailoring seams and small highlights retain the polished detail level of
	# the classic texture without reviving the original gray pinstripe pattern.
	detail.line((1, 178, 1, 473), fill=ORANGE_DARK, width=2)
	detail.line((219, 178, 219, 473), fill=ORANGE_DARK, width=2)
	detail.line((301, 178, 301, 473), fill=ORANGE_DARK, width=2)
	detail.line((510, 178, 510, 473), fill=ORANGE_DARK, width=2)
	detail.line((2, 179, 2, 473), fill=ORANGE_LIGHT, width=1)
	detail.line((218, 179, 218, 473), fill=ORANGE_LIGHT, width=1)

	OUTPUT.parent.mkdir(parents=True, exist_ok=True)
	result.save(OUTPUT, optimize=True)

	comparison = Image.new("RGB", (1024, 512), (28, 30, 34))
	comparison.paste(source, (0, 0))
	comparison.paste(result, (512, 0))
	QA.parent.mkdir(parents=True, exist_ok=True)
	comparison.save(QA, optimize=True)

	coverage = navy_pixels / (source.width * source.height)
	if not 0.15 <= coverage <= 0.60:
		raise ValueError(f"unexpected navy panel coverage: {coverage:.3%}")

	print(OUTPUT)
	print(QA)
	print(f"navy panel coverage: {coverage:.2%}")


if __name__ == "__main__":
	build()
