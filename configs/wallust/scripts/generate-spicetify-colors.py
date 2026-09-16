#!/usr/bin/env python3
"""Generate Spotify's spicetify colour scheme from the current wallpaper palette.

Writes ~/.cache/wal/colors-spicetify.ini, which `pywal-spicetify wal` copies
into the wal theme's color.ini as the [pywal] section and applies.

This replaces a wallust template that mapped raw palette slots onto spicetify's
legacy key names (accent, banner, header...). Current Spotify builds only read
the modern keys below, so every missing one fell back to Spotify's stock green
and grey, and the slots that did land were unconditioned (a near-black
"accent", body text in the cursor colour). Roles here follow quickshell's
Commons/Color.qml so Spotify matches the bar.
"""

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

    # Same conditioning and contrast targets as Color.qml / Theme.qml defaults.
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
        # Referenced by configs/spotify/user.css, not by Spotify itself.
        ("card-background", highlight),
        ("card-hover", highlight),
        ("gradienttop", card),
        ("gradientbottom", bg),
    ]

    width = max(len(k) for k, _ in values)
    body = "".join("%s = %s\n" % (k.ljust(width), rgb_to_hex(v)) for k, v in values)
    tmp = OUT + ".tmp"
    with open(tmp, "w") as fh:
        fh.write(body)
    os.replace(tmp, OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
