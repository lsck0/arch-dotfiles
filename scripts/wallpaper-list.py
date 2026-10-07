#!/usr/bin/env python3
"""List the wallpapers worth showing, one absolute path per line.

Usage: wallpaper-list [--screen WxH] [--resolve NAME]

secrets/wallpapers/ (unlocked) shadows wallpapers/ by file name, so a purchased high-res copy replaces
its public low-res one. For a screen of WxH physical pixels (default 3840x2160) an image is left out when
filling it would visibly upscale the image (UPSCALE_MAX), or crop away more than CROP_FRACTION_MAX
of its area, so a 4K screen gets 4K images only and smaller screens get nearly everything.
--resolve prints the path one name resolves to.
"""

import sys
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[1]
PUBLIC_DIR = REPO / "wallpapers"
SECRET_DIR = REPO / "secrets/wallpapers"
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".gif", ".webp"}
SCREEN_DEFAULT = (3840, 2160)
# filling a screen crops what does not fit; more than this and the picture loses its composition
CROP_FRACTION_MAX = 0.10
# upscaling by this little is invisible; beyond it the picture turns soft
UPSCALE_MAX = 1.05
CACHE = Path.home() / ".cache/wallpaper-list/sizes.tsv"


def secrets_unlocked():
    probe = REPO / "secrets/age.txt"
    return probe.is_file() and not probe.read_bytes()[:10].lstrip(b"\0").startswith(b"GITCRYPT")


def wallpapers_by_name():
    dirs = [PUBLIC_DIR] + ([SECRET_DIR] if secrets_unlocked() and SECRET_DIR.is_dir() else [])
    return {p.name: p for d in dirs for p in sorted(d.iterdir()) if p.suffix.lower() in IMAGE_SUFFIXES}


def sizes_load():
    sizes = {}
    if CACHE.is_file():
        for line in CACHE.read_text().splitlines():
            path, mtime, width, height = line.split("\t")
            sizes[path] = (float(mtime), int(width), int(height))
    return sizes


# header reads only, cached by mtime, so listing stays instant after the first run
def size_of(path, sizes):
    mtime = path.stat().st_mtime
    cached = sizes.get(str(path))
    if cached and cached[0] == mtime:
        return cached[1:]
    with Image.open(path) as image:
        sizes[str(path)] = (mtime, *image.size)
    return image.size


def fits_screen(width, height, screen):
    screen_width, screen_height = screen
    fill_scale = max(screen_width / width, screen_height / height)
    cropped_area = width * height * fill_scale**2 - screen_width * screen_height
    return fill_scale <= UPSCALE_MAX and cropped_area / (width * height * fill_scale**2) <= CROP_FRACTION_MAX


def screen_parse(text):
    width, _, height = text.lower().partition("x")
    return int(width), int(height)


def main():
    args = sys.argv[1:]
    screen = SCREEN_DEFAULT
    if "--resolve" in args:
        name = Path(args[args.index("--resolve") + 1]).name
        path = wallpapers_by_name().get(name)
        sys.exit(print(path) if path else f"wallpaper-list: no wallpaper named {name}")
    if "--screen" in args:
        screen = screen_parse(args[args.index("--screen") + 1])
    sizes = sizes_load()
    for path in sorted(wallpapers_by_name().values()):
        width, height = size_of(path, sizes)
        if fits_screen(width, height, screen):
            print(path)
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text("".join(f"{p}\t{m}\t{w}\t{h}\n" for p, (m, w, h) in sizes.items()))


if __name__ == "__main__":
    main()
