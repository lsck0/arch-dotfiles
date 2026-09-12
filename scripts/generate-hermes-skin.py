#!/usr/bin/env python3
"""Generate a Hermes skin from the current wallpaper palette.

Hermes has a real, documented theming SDK — see
/opt/hermes-agent/hermes_cli/skin_engine.py — and it is unusually good for
this purpose: a single YAML in ~/.hermes/skins/<name>.yaml themes the CLI, the
TUI *and* the Electron desktop app at once, because the gateway resolves the
active skin and pushes it to every surface. So this writes one file rather
than reaching into three.

That is also why nothing here touches /opt/hermes-agent: the package's own
themes are `presets.ts`/built-ins, and editing them would be undone by the
next update. A user skin is the supported seam.

Colour discipline is the same as everywhere else in this repo (see
scripts/lib/palette.py): the background is tone-mapped into a dark band, every
surface is lifted off it rather than pulled from the photo, and every
foreground is computed against the surface it is drawn on rather than assigned
from a palette slot. Hermes' schema has ~40 colour keys and most of them are
text on a specific background, so slot-assignment would reproduce the exact
low-contrast pairings that made nemo unreadable.

Run with --activate to also switch Hermes to this skin (only needed once;
after that the file is regenerated in place and Hermes picks it up).
"""

import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "lib"))

from palette import (  # noqa: E402
    BG_VALUE_MAX,
    BG_VALUE_MIN,
    contrast,
    dim_toward,
    hex_to_rgb,
    lift,
    mix,
    readable_on,
    rgb_to_hex,
    semantic,
    tone_map,
    vivify,
)

WHITE = (1.0, 1.0, 1.0)

CACHE = os.path.expanduser("~/.cache/wal/colors.json")
HERMES_HOME = os.environ.get("HERMES_HOME") or os.path.expanduser("~/.hermes")
SKIN_NAME = "wallust"
OUT = os.path.join(HERMES_HOME, "skins", SKIN_NAME + ".yaml")


def main():
    try:
        with open(CACHE) as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        print("generate-hermes-skin: cannot read %s: %s" % (CACHE, exc), file=sys.stderr)
        return 1

    special, colors = data.get("special", {}), data.get("colors", {})

    def slot(name, fallback):
        try:
            return hex_to_rgb(colors.get(name) or special.get(name) or fallback)
        except (ValueError, IndexError):
            return hex_to_rgb(fallback)

    bg = tone_map(slot("background", "#0b1019"), BG_VALUE_MIN, BG_VALUE_MAX)
    raw_fg = slot("foreground", "#c2c3c5")
    accent = vivify(slot("color4", "#B68B74"), 0.45, 0.55)
    alt = vivify(slot("color5", "#A76495"), 0.35, 0.55)
    cool = vivify(slot("color6", "#A76495"), 0.35, 0.55)

    # Surfaces, lifted off the base rather than taken from the photo.
    status_bg = lift(bg, 0.045)
    menu_bg = lift(bg, 0.045)
    menu_current = lift(bg, 0.11)

    fg = readable_on(bg, raw_fg, 7.0)
    # De-emphasis needs a CEILING, not a floor: `readable_on(..., 2.4)` leaves
    # an already-legible foreground untouched, so "dim" came out identical to
    # body text.
    dim = dim_toward(fg, bg, 2.6)

    # Semantic roles are hue-anchored, not slot-derived. On this wallpaper
    # (all blues and pinks, no red or green) taking them from colour1/2/3 gave
    # a BLUE error, a PURPLE ok and a PINK warning — every contrast check
    # passed and every one of them meant the wrong thing.
    urgent = semantic("error", accent, bg)
    good = semantic("ok", accent, bg)
    warn = semantic("warn", accent, bg)

    # Diff fills, computed here (not inline in `palette`) because the word
    # colors below need to contrast against THEM, not against `bg`.
    diff_added_bg = mix(good, WHITE, 0.88)
    diff_removed_bg = mix(urgent, WHITE, 0.88)

    def on(surface, colour, ratio=4.5):
        return rgb_to_hex(readable_on(surface, colour, ratio), "#")

    def hx(c):
        return rgb_to_hex(c, "#")

    palette = {
        "background": hx(bg),

        # Banner / panels
        "banner_border": on(bg, accent, 3.0),
        "banner_title": on(bg, accent, 4.5),
        "banner_accent": on(bg, accent, 4.5),
        "banner_dim": hx(dim),
        "banner_text": hx(fg),

        # General UI
        "ui_accent": on(bg, accent, 4.5),
        "ui_label": on(bg, alt, 4.5),
        "ui_ok": on(bg, good, 4.5),
        "ui_error": on(bg, urgent, 4.5),
        "ui_warn": on(bg, warn, 4.5),
        "ui_tool": on(bg, accent, 4.5),
        "ui_thinking": hx(dim),

        # Diffs. diff_added/diff_removed are FILLS (backgroundColor on the
        # whole line); diff_added_word/diff_removed_word are the TEXT drawn
        # on top of that same fill (see hermes_cli/tui_dist/entry.js: one
        # Text node gets `backgroundColor: diffAdded, color: diffAddedWord`)
        # — they are not drawn on the app background, so contrast-checking
        # them against `bg` (as a first version of this did) picked a vivid
        # green/red that barely contrasts against the pale fill beneath it,
        # reading as a near-blank white/pale blob. Fill stays pale (mixed
        # 88% toward white, matching the built-in skin's own #dcffdc/
        # #ffdcdc pastel intensity rather than a vivid full-bleed color);
        # word color is contrast-checked against THAT fill instead —
        # readable_on auto-picks the dark pole since the fill is light.
        "diff_added": hx(diff_added_bg),
        "diff_removed": hx(diff_removed_bg),
        "diff_added_word": on(diff_added_bg, good, 4.5),
        "diff_removed_word": on(diff_removed_bg, urgent, 4.5),

        # Syntax
        "syntax_string": on(bg, good, 4.5),
        "syntax_number": on(bg, cool, 4.5),
        "syntax_keyword": on(bg, accent, 4.5),
        "syntax_comment": hx(dim),

        # Prompt / response
        "prompt": hx(fg),
        "input_rule": on(bg, accent, 3.0),
        "response_border": on(bg, accent, 3.0),
        "session_label": on(bg, alt, 4.5),
        "session_border": hx(dim),

        # Status bar — its own surface, so its text is measured against that
        # rather than against the app background.
        "status_bar_bg": hx(status_bg),
        "status_bar_text": on(status_bg, raw_fg, 4.5),
        "status_bar_strong": on(status_bg, accent, 4.5),
        "status_bar_dim": on(status_bg, raw_fg, 2.4),
        "status_bar_good": on(status_bg, good, 4.5),
        "status_bar_warn": on(status_bg, warn, 4.5),
        "status_bar_bad": on(status_bg, warn, 4.5),
        "status_bar_critical": on(status_bg, urgent, 4.5),

        # TUI chrome
        "voice_status_bg": hx(status_bg),
        "selection_bg": hx(menu_current),
        "completion_menu_bg": hx(menu_bg),
        "completion_menu_current_bg": hx(menu_current),
        "completion_menu_meta_bg": hx(menu_bg),
        "completion_menu_meta_current_bg": hx(menu_current),
    }

    skin = {
        "name": SKIN_NAME,
        "description": "Generated from the current wallpaper (wallust) — do not hand-edit",
        "colors": palette,
    }

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    # Hand-rolled YAML rather than pulling in pyyaml: the document is a flat
    # map of strings and quoting every value is unambiguous, so a dependency
    # would buy nothing. Values are hex from rgb_to_hex, so they cannot
    # contain a quote.
    lines = [
        "# Generated by scripts/generate-hermes-skin.py from the current",
        "# wallpaper palette. Regenerated on every wallpaper change — any edit",
        "# here is lost. Change the generator instead.",
        "name: %s" % SKIN_NAME,
        'description: "%s"' % skin["description"],
        "colors:",
    ]
    for key, value in palette.items():
        lines.append('  %s: "%s"' % (key, value))
    tmp = OUT + ".tmp"
    with open(tmp, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    os.replace(tmp, OUT)

    if "--report" in sys.argv:
        checks = [
            ("banner_text", "background"), ("ui_accent", "background"),
            ("ui_error", "background"), ("ui_ok", "background"),
            ("ui_warn", "background"), ("status_bar_text", "status_bar_bg"),
            ("status_bar_strong", "status_bar_bg"),
            ("status_bar_critical", "status_bar_bg"),
        ]
        for f, b in checks:
            ratio = contrast(hex_to_rgb(palette[f]), hex_to_rgb(palette[b]))
            print("%-20s %s on %s  %.2f:1  %s"
                  % (f, palette[f], palette[b], ratio,
                     "OK" if ratio >= 4.5 else "LOW"))

    print("wrote %s (%d colours)" % (OUT, len(palette)))

    if "--activate" in sys.argv:
        # Only needed once. `hermes skin use` writes display.skin into
        # config.yaml; after that this script just rewrites the file the
        # active skin points at.
        try:
            subprocess.run(["hermes", "skin", "use", SKIN_NAME],
                           check=False, timeout=60,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            print("activated skin '%s'" % SKIN_NAME)
        except (OSError, subprocess.SubprocessError) as exc:
            print("could not activate: %s" % exc, file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
