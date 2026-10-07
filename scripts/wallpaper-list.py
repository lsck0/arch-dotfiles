#!/usr/bin/env python3
"""List the wallpapers worth showing, one absolute path per line.

Usage: wallpaper-list [--screen WxH] | --resolve NAME

secrets/wallpapers/ shadows wallpapers/ by file name, so a purchased high-res copy replaces its public
low-res one; a secret counts only while it is plaintext (git-crypt unlocked) and readable. For a screen
of WxH physical pixels (default 3840x2160) an image is left out when filling it would visibly upscale
the image (UPSCALE_MAX), or crop away more than CROP_FRACTION_MAX of its area, so a 4K screen gets 4K
images only and smaller screens get nearly everything.
--resolve prints the path a bare file name resolves to, secrets first, unfiltered by screen.
"""

import argparse
import os
import sys
from pathlib import Path

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


# a locked git-crypt file begins with "\0GITCRYPT"; an unreadable one is as good as locked
def is_plaintext(path):
    try:
        with open(path, "rb") as fh:
            return not fh.read(10).lstrip(b"\0").startswith(b"GITCRYPT")
    except OSError:
        return False


def images_in(directory, usable=lambda p: True):
    if not directory.is_dir():
        return {}
    return {
        p.name: p for p in directory.iterdir() if p.suffix.lower() in IMAGE_SUFFIXES and p.is_file() and usable(p)
    }


def wallpapers_by_name():
    return images_in(PUBLIC_DIR) | images_in(SECRET_DIR, is_plaintext)


def resolve(name):
    """Best path for a bare file name, or None."""
    for directory in (SECRET_DIR, PUBLIC_DIR):
        path = directory / name
        if path.is_file() and (directory is PUBLIC_DIR or is_plaintext(path)):
            return path
    return None


def sizes_load():
    sizes = {}
    try:
        for line in CACHE.read_text().splitlines():
            path, mtime, width, height = line.split("\t")
            sizes[path] = (float(mtime), int(width), int(height))
    except (OSError, ValueError):
        pass  # a missing or torn cache only costs a rescan
    return sizes


# header reads only, cached by mtime, so listing stays instant after the first run
def size_of(path, sizes):
    from PIL import Image

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
    filled_area = width * height * fill_scale**2
    return fill_scale <= UPSCALE_MAX and 1 - screen_width * screen_height / filled_area <= CROP_FRACTION_MAX


def screen_parse(text):
    width, sep, height = text.lower().partition("x")
    if not (sep and width.isdigit() and height.isdigit() and int(width) and int(height)):
        raise argparse.ArgumentTypeError(f"not WxH: {text}")
    return int(width), int(height)


def main():
    parser = argparse.ArgumentParser(prog="wallpaper-list")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--screen", type=screen_parse, default=SCREEN_DEFAULT)
    mode.add_argument("--resolve", metavar="NAME")
    args = parser.parse_args()

    if args.resolve is not None:
        name = args.resolve
        path = resolve(name) if name and "/" not in name and name not in (".", "..") else None
        if not path:
            sys.exit(f"wallpaper-list: no wallpaper named {name}")
        print(path)
        return

    sizes = sizes_load()
    seen = {}
    for path in sorted(wallpapers_by_name().values()):
        try:
            width, height = size_of(path, sizes)
        except Exception as error:  # an LFS pointer or a broken file is never eligible
            print(f"wallpaper-list: skipping {path}: {error}", file=sys.stderr)
            continue
        seen[str(path)] = sizes[str(path)]
        if fits_screen(width, height, args.screen):
            print(path)
    # only entries still on disk, written atomically so a concurrent run never reads half a file
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    tmp = CACHE.with_name(f"{CACHE.name}.{os.getpid()}")
    tmp.write_text("".join(f"{p}\t{m}\t{w}\t{h}\n" for p, (m, w, h) in seen.items()))
    os.replace(tmp, CACHE)


if __name__ == "__main__":
    main()
