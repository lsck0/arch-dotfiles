#!/usr/bin/env python3
"""Write ~/.cache/wal/colors-spicetify.ini and the wal theme color.ini."""

import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "lib"))

from palette import (  # noqa: E402
    BG_VALUE_MAX,
    BG_VALUE_MIN,
    dim_toward,
    hex_to_rgb,
    lift,
    readable_on,
    rgb_to_hex,
    selection_pair,
    semantic,
    tone_map,
    vivify,
)

CACHE = os.path.expanduser("~/.cache/wal/colors.json")
OUT = os.path.expanduser("~/.cache/wal/colors-spicetify.ini")
THEME_INI = os.path.expanduser("~/.config/spicetify/Themes/wal/color.ini")


def main():
    try:
        with open(CACHE) as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        print("generate-spicetify-colors: cannot read %s: %s" % (CACHE, exc), file=sys.stderr)
        return 1

    special, colors = data.get("special", {}), data.get("colors", {})

    def slot(name, fallback):
        try:
            return hex_to_rgb(colors.get(name) or special.get(name) or fallback)
        except (ValueError, IndexError):
            return hex_to_rgb(fallback)

    bg = tone_map(slot("background", "#0b1019"), BG_VALUE_MIN, BG_VALUE_MAX)
    fg = readable_on(bg, slot("foreground", "#c2c3c5"), 7.0)
    accent = readable_on(bg, vivify(slot("color4", "#B68B74"), 0.45, 0.55), 3.0)
    muted = readable_on(bg, slot("color8", "#5a616e"), 1.9)
    subtext = dim_toward(fg, bg, 4.6)

    elevated = lift(bg, 0.045)
    card = lift(bg, 0.03)
    highlight = lift(bg, 0.075)
    highlight_elevated = lift(bg, 0.11)
    notify_bg, _ = selection_pair(accent, fg)

    values = [
        ("text", fg),
        ("subtext", subtext),
        ("main", bg),
        ("main-elevated", elevated),
        ("highlight", highlight),
        ("highlight-elevated", highlight_elevated),
        ("sidebar", bg),
        ("player", bg),
        ("card", card),
        ("shadow", (0.0, 0.0, 0.0)),
        ("selected-row", fg),
        ("button", accent),
        ("button-active", lift(accent, 0.08)),
        ("button-disabled", muted),
        ("tab-active", highlight_elevated),
        ("notification", notify_bg),
        ("notification-error", semantic("error", accent, bg, 3.0)),
        ("misc", muted),
        # used by configs/spotify/user.css
        ("card-background", highlight),
        ("card-hover", highlight),
        ("gradienttop", card),
        ("gradientbottom", bg),
    ]

    width = max(len(k) for k, _ in values)
    body = "".join("%s = %s\n" % (k.ljust(width), rgb_to_hex(v)) for k, v in values)
    write(OUT, body)
    # color.ini is a symlink into the repo, write through it
    if os.path.isdir(os.path.dirname(THEME_INI)):
        write(os.path.realpath(THEME_INI), "[pywal]\n" + body)
    return 0


def write(path, body):
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        fh.write(body)
    os.replace(tmp, path)


if __name__ == "__main__":
    sys.exit(main())
