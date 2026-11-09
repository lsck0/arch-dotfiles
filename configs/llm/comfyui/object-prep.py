"""A reference image recentred the way Hunyuan3D's own pipeline expects: the object cropped, scaled to fill most of a
square, everything else pure white (a faint shadow or floor would otherwise come back as geometry).

Run with ComfyUI's venv python: object-prep.py <image> <out.png>. An image whose corners are not near white (a photo,
a scene) is copied unchanged: there the background cannot be told apart by colour.
"""

import sys

import numpy as np
from PIL import Image, ImageFilter

SIZE = 1024
# share of the square the object's longer side fills (Hunyuan3D's preprocessing uses a 0.15 border)
FILL = 0.85
# a pixel this far below white on any channel belongs to the object
THRESHOLD = 30
CORNER = 16


def main() -> None:
    src, out = sys.argv[1], sys.argv[2]
    img = Image.open(src).convert("RGB")
    a = np.asarray(img, dtype=np.int16)
    corners = np.concatenate([a[:CORNER, :CORNER], a[:CORNER, -CORNER:], a[-CORNER:, :CORNER], a[-CORNER:, -CORNER:]])
    if corners.min() < 255 - THRESHOLD:
        img.save(out)
        return
    mask = (255 - a).max(axis=2) > THRESHOLD
    # drop specks and fill pinholes so the bbox and the cutout follow the object, not noise
    m = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MedianFilter(5))
    m = m.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
    box = m.getbbox()
    if box is None:
        img.save(out)
        return
    white = Image.new("RGB", img.size, (255, 255, 255))
    cut = Image.composite(img, white, m.filter(ImageFilter.GaussianBlur(1))).crop(box)
    scale = SIZE * FILL / max(cut.size)
    cut = cut.resize((max(1, round(cut.width * scale)), max(1, round(cut.height * scale))), Image.LANCZOS)
    canvas = Image.new("RGB", (SIZE, SIZE), (255, 255, 255))
    canvas.paste(cut, ((SIZE - cut.width) // 2, (SIZE - cut.height) // 2))
    canvas.save(out)


if __name__ == "__main__":
    main()
