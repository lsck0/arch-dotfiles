"""A reference image recentred the way Hunyuan3D's own pipeline expects: the object cropped, scaled to fill most of a
square, everything else pure white (a faint shadow or floor would otherwise come back as geometry).

Run with ComfyUI's venv python: object-prep.py <image> <out.png>. The background is the corners' colour (comfy-gen asks
for a chroma-green screen, a colour no object shares; its green spill on the edges is pulled back); an image whose
corners are not one plain colour (a photo, a scene) is copied unchanged, since there the background cannot be told
apart by colour.
"""

import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

SIZE = 1024
# share of the square the object's longer side fills (Hunyuan3D's preprocessing uses a 0.15 border)
FILL = 0.85
# a pixel this far from the background colour on any channel belongs to the object
THRESHOLD = 30
# corners spread wider than this per channel are no plain background
CORNER_SPREAD = 24
# corners this much greener than red and blue are a green screen
GREEN_DOMINANCE = 40
# share of the screen's green dominance from which a pixel counts as screen
SCREEN_SHARE = 0.6
CORNER = 16


def main() -> None:
    src, out = sys.argv[1], sys.argv[2]
    img = Image.open(src).convert("RGB")
    a = np.asarray(img, dtype=np.int16)
    corners = np.concatenate(
        [a[:CORNER, :CORNER], a[:CORNER, -CORNER:], a[-CORNER:, :CORNER], a[-CORNER:, -CORNER:]]
    ).reshape(-1, 3)
    background = np.median(corners, axis=0)
    green = a[..., 1] - np.maximum(a[..., 0], a[..., 2])
    corner_green = corners[:, 1] - np.maximum(corners[:, 0], corners[:, 2])
    if corner_green.min() > GREEN_DOMINANCE:
        # a green screen: whatever is at least half as green as the screen is screen, its gradient and shadows
        # included; a light object's green reflection stays well below that
        mask = green < np.median(corner_green) * SCREEN_SHARE
    elif (corners.max(axis=0) - corners.min(axis=0)).max() > CORNER_SPREAD:
        img.save(out)
        return
    else:
        mask = np.abs(a - background).max(axis=2) > THRESHOLD
    # drop specks and fill pinholes so the bbox and the cutout follow the object, not noise
    m = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MedianFilter(5))
    m = m.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
    # the object is the largest region: a shadow speck or a stray patch of screen is dropped
    labels, count = ndimage.label(np.asarray(m) > 0)
    if count > 1:
        sizes = ndimage.sum(np.ones_like(labels), labels, range(1, count + 1))
        m = Image.fromarray(((labels == (int(np.argmax(sizes)) + 1)) * 255).astype(np.uint8))
    box = m.getbbox()
    if box is None:
        img.save(out)
        return
    # green-screen spill: where green outweighs red and blue on a green background, cap it at their larger value
    if corner_green.min() > GREEN_DOMINANCE:
        rgb = np.asarray(img, dtype=np.int16).copy()
        cap = np.maximum(rgb[..., 0], rgb[..., 2])
        rgb[..., 1] = np.minimum(rgb[..., 1], cap)
        img = Image.fromarray(rgb.astype(np.uint8))
    white = Image.new("RGB", img.size, (255, 255, 255))
    cut = Image.composite(img, white, m.filter(ImageFilter.GaussianBlur(1))).crop(box)
    scale = SIZE * FILL / max(cut.size)
    cut = cut.resize((max(1, round(cut.width * scale)), max(1, round(cut.height * scale))), Image.LANCZOS)
    canvas = Image.new("RGB", (SIZE, SIZE), (255, 255, 255))
    canvas.paste(cut, ((SIZE - cut.width) // 2, (SIZE - cut.height) // 2))
    canvas.save(out)


if __name__ == "__main__":
    main()
