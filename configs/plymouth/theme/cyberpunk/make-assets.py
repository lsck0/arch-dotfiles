#!/usr/bin/env python3
# regenerates the theme pngs

import struct
import zlib
from pathlib import Path

ACCENT = (0x39, 0xBA, 0xE6, 0xFF)
TRACK = (0x39, 0xBA, 0xE6, 0x33)


def write_png(path, width, height, rgba):
    raw = bytearray()
    row = bytes(rgba) * width
    for _ in range(height):
        raw.append(0)  # filter type none
        raw.extend(row)

    def chunk(tag, data):
        out = struct.pack(">I", len(data)) + tag + data
        return out + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", ihdr)
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    Path(path).write_bytes(png)


def main():
    here = Path(__file__).resolve().parent
    write_png(here / "bar_fg.png", 360, 2, ACCENT)
    write_png(here / "bar_bg.png", 360, 2, TRACK)
    write_png(here / "caret.png", 12, 20, ACCENT)
    print("wrote bar_fg.png bar_bg.png caret.png")


if __name__ == "__main__":
    main()
