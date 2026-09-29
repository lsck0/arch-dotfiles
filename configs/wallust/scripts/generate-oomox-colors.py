#!/usr/bin/env python3
"""Generate ~/.cache/wal/colors-oomox with contrast guarantees."""

import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "lib"))

from palette import (  # noqa: E402
    TEXT_RATIO,
    BG_VALUE_MIN,
    BG_VALUE_MAX,
    contrast,
    hex_to_rgb,
    lift,
    readable_on,
    rgb_to_hex,
    selection_pair,
    tone_map,
    vivify,
)

CACHE = os.path.expanduser("~/.cache/wal/colors.json")
OUT = os.path.expanduser("~/.cache/wal/colors-oomox")


def main():
    try:
        with open(CACHE) as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        print("generate-oomox-colors: cannot read %s: %s" % (CACHE, exc),
              file=sys.stderr)
        return 1

    special = data.get("special", {})
    colors = data.get("colors", {})

    def slot(name, fallback):
        try:
            return hex_to_rgb(colors.get(name) or special.get(name) or fallback)
        except (ValueError, IndexError):
            return hex_to_rgb(fallback)

    bg = tone_map(slot("background", "#0b1019"), BG_VALUE_MIN, BG_VALUE_MAX)
    raw_fg = slot("foreground", "#c2c3c5")
    accent = vivify(slot("color4", "#B68B74"), 0.45, 0.55)

    menu_bg = lift(bg, 0.045)
    txt_bg = lift(bg, 0.02)
    btn_bg = lift(bg, 0.075)
    hdr_bg = lift(bg, 0.03)

    sel_bg, sel_fg = selection_pair(accent, raw_fg)

    values = {
        "NAME": "wal",
        "BG": rgb_to_hex(bg),
        "FG": rgb_to_hex(readable_on(bg, raw_fg)),
        "MENU_BG": rgb_to_hex(menu_bg),
        "MENU_FG": rgb_to_hex(readable_on(menu_bg, raw_fg)),
        "SEL_BG": rgb_to_hex(sel_bg),
        "SEL_FG": rgb_to_hex(sel_fg),
        "TXT_BG": rgb_to_hex(txt_bg),
        "TXT_FG": rgb_to_hex(readable_on(txt_bg, raw_fg)),
        "BTN_BG": rgb_to_hex(btn_bg),
        "BTN_FG": rgb_to_hex(readable_on(btn_bg, raw_fg)),
        "HDR_BTN_BG": rgb_to_hex(hdr_bg),
        "HDR_BTN_FG": rgb_to_hex(readable_on(hdr_bg, raw_fg)),
        "GTK3_GENERATE_DARK": "True",
        "ROUNDNESS": "3",
        "SPACING": "3",
        "GRADIENT": "0.0",
    }

    order = ["NAME", "BG", "FG", "MENU_BG", "MENU_FG", "SEL_BG", "SEL_FG",
             "TXT_BG", "TXT_FG", "BTN_BG", "BTN_FG", "HDR_BTN_BG",
             "HDR_BTN_FG", "GTK3_GENERATE_DARK", "ROUNDNESS", "SPACING",
             "GRADIENT"]

    body = "".join("%s=%s\n" % (k, values[k]) for k in order)
    # atomic write, themix reads this path
    tmp = OUT + ".tmp"
    with open(tmp, "w") as fh:
        fh.write(body)
    os.replace(tmp, OUT)

    if "--report" in sys.argv:
        pairs = [("FG/BG", "FG", "BG"), ("MENU", "MENU_FG", "MENU_BG"),
                 ("SEL", "SEL_FG", "SEL_BG"), ("TXT", "TXT_FG", "TXT_BG"),
                 ("BTN", "BTN_FG", "BTN_BG"), ("HDR", "HDR_BTN_FG", "HDR_BTN_BG")]
        for label, f, b in pairs:
            ratio = contrast(hex_to_rgb(values[f]), hex_to_rgb(values[b]))
            print("%-6s %s on %s  %.2f:1  %s"
                  % (label, values[f], values[b], ratio,
                     "OK" if ratio >= TEXT_RATIO else "LOW"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
