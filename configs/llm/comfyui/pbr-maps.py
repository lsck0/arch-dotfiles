"""A generated albedo made seamless, plus height, normal and roughness maps derived from it.

Run with ComfyUI's venv python (numpy and Pillow): pbr-maps.py <image> <out dir>. Writes albedo.png, height.png,
normal.png (OpenGL, green up, as Blender expects) and roughness.png.
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

NORMAL_STRENGTH = 4.0
# roughness spans this range: cavities rough, raised surfaces a little smoother
ROUGHNESS_LOW, ROUGHNESS_HIGH = 0.45, 0.95
HEIGHT_BLUR = 1.5
# share of the tile, per edge, where the image is cross-faded with its half-shifted copy
SEAM_BAND = 0.2


def seamless_axis(img: np.ndarray, axis: int) -> np.ndarray:
    """Blends the image with itself shifted half a tile along one axis: its edges then meet, its middle is untouched."""
    size = img.shape[axis]
    shifted = np.roll(img, size // 2, axis=axis)
    # 1 everywhere but a band at each edge, easing to 0 at the edge itself: the ghosting a blend leaves stays in the band
    edge = np.minimum(np.arange(size) + 0.5, size - np.arange(size) - 0.5) / (size * SEAM_BAND)
    t = np.clip(edge, 0.0, 1.0)
    weight = t * t * (3.0 - 2.0 * t)
    shape = [1] * img.ndim
    shape[axis] = size
    weight = weight.reshape(shape)
    return img * weight + shifted * (1.0 - weight)


def normalize(a: np.ndarray) -> np.ndarray:
    lo, hi = np.percentile(a, 1), np.percentile(a, 99)
    return np.clip((a - lo) / max(hi - lo, 1e-6), 0.0, 1.0)


def main() -> None:
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    rgb = np.asarray(Image.open(src).convert("RGB"), dtype=np.float32) / 255.0
    # separable: the second pass keeps the first axis seamless, so both axes tile
    rgb = seamless_axis(seamless_axis(rgb, 1), 0)
    Image.fromarray((rgb * 255.0 + 0.5).astype(np.uint8)).save(out / "albedo.png")

    luma = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    blurred = Image.fromarray((luma * 255.0).astype(np.uint8)).filter(ImageFilter.GaussianBlur(HEIGHT_BLUR))
    height = normalize(np.asarray(blurred, dtype=np.float32) / 255.0)
    Image.fromarray((height * 255.0 + 0.5).astype(np.uint8)).save(out / "height.png")

    # central differences that wrap around, so the normal map tiles like the albedo
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    normal = np.dstack((-dx * NORMAL_STRENGTH, dy * NORMAL_STRENGTH, np.ones_like(height)))
    normal /= np.linalg.norm(normal, axis=2, keepdims=True)
    Image.fromarray(((normal * 0.5 + 0.5) * 255.0 + 0.5).astype(np.uint8)).save(out / "normal.png")

    roughness = ROUGHNESS_HIGH - (ROUGHNESS_HIGH - ROUGHNESS_LOW) * height
    Image.fromarray((roughness * 255.0 + 0.5).astype(np.uint8)).save(out / "roughness.png")


if __name__ == "__main__":
    main()
