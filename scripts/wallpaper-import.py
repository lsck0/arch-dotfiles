#!/usr/bin/env python3
"""Import purchased high-res wallpapers into secrets/wallpapers/.

Usage: wallpaper-import <file|dir|zip>...

Each image is matched against wallpapers/ by its downscaled pixels. A match is saved under the
repo file's name, so it shadows the low-res copy (scripts/switch-wallpaper.sh prefers secrets/);
anything without a match keeps a slug of its own name. Only the default secrets checkout is used,
never a locked one.
"""

import io
import re
import sys
import zipfile
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[1]
PUBLIC_DIR = REPO / "wallpapers"
SECRET_DIR = REPO / "secrets/wallpapers"
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp"}
# small enough to ignore crop and compression differences, large enough to tell artworks apart
FINGERPRINT_SIZE = (32, 18)
# mean absolute grey difference per pixel (0-255) below which two images are the same artwork
MATCH_DISTANCE_MAX = 12


# grey level under which a border row or column counts as letterbox padding
LETTERBOX_LEVEL_MAX = 16
# trimming works on a small copy, full 4k pixels add nothing but time
THUMBNAIL_SIZE = (1024, 1024)


# letterboxed low-res copies would never match their unpadded originals, so padding is trimmed first
def fingerprint_from_image(image):
    grey = image.convert("L")
    grey.thumbnail(THUMBNAIL_SIZE)
    content = grey.point(lambda v: 255 if v > LETTERBOX_LEVEL_MAX else 0).getbbox()
    return list(grey.crop(content or (0, 0, *grey.size)).resize(FINGERPRINT_SIZE, Image.Resampling.LANCZOS).tobytes())


def fingerprint_distance(a, b):
    return sum(abs(x - y) for x, y in zip(a, b)) / len(a)


def slug_from_name(name):
    return re.sub(r"[^a-z0-9]+", "-", Path(name).stem.lower()).strip("-")


def images_from_args(args):
    """(name, bytes) for every image in the given files, directories and zips."""
    for arg in map(Path, args):
        if arg.is_dir():
            yield from images_from_args(sorted(str(p) for p in arg.rglob("*") if p.is_file()))
        elif arg.suffix.lower() == ".zip":
            with zipfile.ZipFile(arg) as archive:
                for info in archive.infolist():
                    if Path(info.filename).suffix.lower() in IMAGE_SUFFIXES and not info.is_dir():
                        yield Path(info.filename).name, archive.read(info)
        elif arg.suffix.lower() in IMAGE_SUFFIXES:
            yield arg.name, arg.read_bytes()


def secrets_unlocked():
    probe = REPO / "secrets/age.txt"
    return probe.is_file() and not probe.read_bytes()[:10].lstrip(b"\0").startswith(b"GITCRYPT")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    if not secrets_unlocked():
        sys.exit("wallpaper-import: secrets/ is locked, unlock it first")
    public = {p.name: fingerprint_from_image(Image.open(p)) for p in sorted(PUBLIC_DIR.iterdir())
              if p.suffix.lower() in IMAGE_SUFFIXES}
    SECRET_DIR.mkdir(parents=True, exist_ok=True)
    for name, data in images_from_args(sys.argv[1:]):
        image = Image.open(io.BytesIO(data))
        candidate = fingerprint_from_image(image)
        best, distance = min(((n, fingerprint_distance(candidate, f)) for n, f in public.items()),
                             key=lambda pair: pair[1], default=(None, float("inf")))
        target = best if distance <= MATCH_DISTANCE_MAX else f"{slug_from_name(name)}{Path(name).suffix.lower()}"
        (SECRET_DIR / target).write_bytes(data)
        how = f"shadows wallpapers/{best}" if target == best else "new, no public match"
        print(f"{name}  {image.width}x{image.height}  -> secrets/wallpapers/{target}  ({how}, distance {distance:.1f})")


if __name__ == "__main__":
    main()
