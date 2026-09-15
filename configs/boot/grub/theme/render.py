#!/usr/bin/env python3
"""Render the ly-style GRUB theme into a directory.

usage: render.py <out_dir> <font_px> <hostname>

GRUB fonts are bitmaps, so the font is rasterized at install time for the
connected display's resolution. Box images are plain 1-colour PNGs, written
by hand to avoid an image library dependency.
"""

import struct
import subprocess
import sys
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
FONTS = [
    "/usr/share/fonts/TTF/0xProtoNerdFontMono-Regular.ttf",
    "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
]
WHITE = (0xFF, 0xFF, 0xFF, 0xFF)
BLACK = (0x00, 0x00, 0x00, 0xFF)


def png(path, width, height, rgba):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))

    rows = b"".join(b"\x00" + bytes(rgba) * width for _ in range(height))
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(rows))
        + chunk(b"IEND", b"")
    )


def pf2_name(path):
    # PFF2 chunks are <4-byte tag><u32 BE length><data>; NAME is a NUL-terminated string.
    data = path.read_bytes()
    i = data.index(b"NAME")
    (length,) = struct.unpack(">I", data[i + 4:i + 8])
    return data[i + 8:i + 8 + length].rstrip(b"\0").decode()


def main():
    out, size, hostname = Path(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
    out.mkdir(parents=True, exist_ok=True)

    # 9-slice box like ly's border: white edges, black inside.
    b = max(1, size // 12)
    for part, (w, h) in {
        "nw": (b, b), "n": (1, b), "ne": (b, b),
        "w": (b, 1), "e": (b, 1),
        "sw": (b, b), "s": (1, b), "se": (b, b),
    }.items():
        png(out / f"box_{part}.png", w, h, WHITE)
    png(out / "box_c.png", 1, 1, BLACK)
    # Selected entry is an inverted bar, as in a tty.
    png(out / "select_c.png", 1, 1, WHITE)

    font_name = ""
    font = next((f for f in FONTS if Path(f).is_file()), None)
    if font:
        pf2 = out / "font.pf2"
        subprocess.run(["grub-mkfont", "-s", str(size), "-o", str(pf2), font], check=True)
        font_name = pf2_name(pf2)
    else:
        print("render.py: no TTF font found, GRUB falls back to its builtin font", file=sys.stderr)

    item_height = size * 3 // 2
    subs = {
        "FONT": font_name,
        "ITEM_HEIGHT": str(item_height),
        "PAD": str(size // 2),
        "TITLE_OFFSET": str(item_height * 3 // 2),
        "HOSTNAME": hostname.replace('"', ""),
    }
    text = (HERE / "theme.txt").read_text()
    for key, val in subs.items():
        text = text.replace(f"@{key}@", val)
    (out / "theme.txt").write_text(text)


if __name__ == "__main__":
    main()
