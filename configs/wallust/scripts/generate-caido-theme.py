#!/usr/bin/env python3
"""Write ~/.cache/wal/colors-caido.css and inject it into EvenBetter's stylesheet."""

import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "lib"))

from palette import (  # noqa: E402
    hsv_to_rgb,
    mix,
    readable_light_on,
    readable_on,
    rgb_to_hex,
    rgb_to_hsv,
    tone_map,
    vivify,
    wal_load,
    write_atomic,
)

OUT = os.path.expanduser("~/.cache/wal/colors-caido.css")
CAIDO_DIR = os.path.expanduser("~/.local/share/caido")
PLUGINS_DB = os.path.join(CAIDO_DIR, "plugins.db")

# evenbetter is a frontend plugin; caido injects its stylesheet into the main document, so a
# :root block appended there themes the whole webview. evenbetter owns the only editable global
# sheet, so the block is reapplied here on every wallpaper change and lost only if it reinstalls.
MARK_START = "/* pywal-theme-start */"
MARK_END = "/* pywal-theme-end */"

# system ui font; caido's ui and its codemirror editors are monospace, matching the terminal look
SYSTEM_FONT = "Kode Mono"
FONT_STACK = '"%s", "Symbols Nerd Font Mono", monospace' % SYSTEM_FONT
EVENBETTER_QUERY = (
    "select p.id from plugins p join plugin_packages pk on p.package_id=pk.id "
    "where pk.manifest_id='evenbetter' and p.kind='frontend' limit 1;"
)

# caido's neutral and accent scales run 900 (darkest) up to 100/200 (lightest); map each scale
# stop to how far it sits along the ramp. the neutral stops are a mix toward a light tint, the
# accent stops lighten (negative) toward white or darken (positive) in value.
NEUTRAL_STOPS = {900: 0.0, 800: 0.06, 700: 0.11, 600: 0.18, 500: 0.30, 400: 0.46, 300: 0.66, 200: 0.83}
SURFACE_LIGHT_STOP = 0.96
ACCENT_STOPS = {100: -0.82, 200: -0.60, 300: -0.40, 400: -0.18, 500: 0.0, 600: 0.14, 700: 0.26, 800: 0.37, 900: 0.50}


def rgb_to_hsl(rgb):
    r, g, b = rgb
    hi, lo = max(rgb), min(rgb)
    light = (hi + lo) / 2
    if hi == lo:
        return 0.0, 0.0, light
    d = hi - lo
    s = d / (2 - hi - lo) if light > 0.5 else d / (hi + lo)
    if hi == r:
        h = ((g - b) / d) % 6
    elif hi == g:
        h = (b - r) / d + 2
    else:
        h = (r - g) / d + 4
    return h / 6, s, light


def hsl_triple(rgb):
    # caido stores these scales as "Hdeg S% L%" and consumes them through hsl()
    h, s, light = rgb_to_hsl(rgb)
    return "%ddeg %d%% %d%%" % (round(h * 360), round(s * 100), round(light * 100))


def darken(rgb, amount):
    h, s, v = rgb_to_hsv(rgb)
    return hsv_to_rgb(h, min(1.0, s * 1.03), v * (1 - amount))


def ramp(base, amount):
    return mix(base, (1.0, 1.0, 1.0), -amount) if amount < 0 else darken(base, amount)


def evenbetter_stylesheet():
    if not os.path.isfile(PLUGINS_DB):
        return None
    try:
        result = subprocess.run(
            ["sqlite3", "-readonly", PLUGINS_DB, EVENBETTER_QUERY],
            capture_output=True, text=True, check=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    plugin_id = result.stdout.strip()
    if not plugin_id:
        return None
    path = os.path.join(CAIDO_DIR, "plugins", plugin_id, "index.css")
    return path if os.path.isfile(path) else None


def inject(path, block):
    with open(path) as fh:
        css = fh.read()
    start = css.find(MARK_START)
    if start != -1:
        end = css.find(MARK_END, start)
        css = css[:start].rstrip() if end == -1 else css[:start] + css[end + len(MARK_END):]
    write_atomic(path, css.rstrip() + "\n" + block)


def main():
    if shutil.which("caido") is None:
        return 0
    slot = wal_load("generate-caido-theme")
    if slot is None:
        return 1

    bg = tone_map(slot("background", "#1a1b26"))
    fg = readable_light_on(bg, slot("foreground", "#c0caf5"), 7.0)
    accent = readable_on(bg, vivify(slot("color4", "#7aa2f7"), 0.55, 0.62), 3.0)
    highlight = readable_on(bg, vivify(slot("color3", "#e0af68"), 0.55, 0.68), 3.0)

    hue, sat, _ = rgb_to_hsv(bg)
    light_neutral = hsv_to_rgb(hue, sat * 0.25, 0.90)

    def neutral(t):
        return mix(bg, light_neutral, t)

    tokens = []
    # neutral ramp drives backgrounds, panels, borders and muted text through gray (hex) and
    # the primevue surface scale (hsl); both are the same ramp in the two formats caido wants.
    for step, t in NEUTRAL_STOPS.items():
        tokens.append(("--c-gray-%d" % step, rgb_to_hex(neutral(t), "#")))
        tokens.append(("--c-surface-%d" % step, hsl_triple(neutral(t))))
    tokens.append(("--c-surface-0", hsl_triple(neutral(SURFACE_LIGHT_STOP))))
    # body text
    tokens.append(("--c-white-100", rgb_to_hex(fg, "#")))
    tokens.append(("--c-fg-default", "var(--c-white-100)"))
    # accent paints the primary button, links and selection; primevue reads the primary scale (hsl)
    for step, amount in ACCENT_STOPS.items():
        tokens.append(("--c-primary-%d" % step, hsl_triple(ramp(accent, amount))))
    tokens += [
        ("--c-bg-primary", rgb_to_hex(accent, "#")),
        ("--c-bg-primary--pressed", rgb_to_hex(darken(accent, 0.14), "#")),
        ("--c-fg-primary", rgb_to_hex(accent, "#")),
        ("--c-border-primary", rgb_to_hex(accent, "#")),
        ("--c-fg-on", rgb_to_hex(readable_light_on(accent, fg), "#")),
    ]
    # highlight is the yellow emphasis colour; primevue reads the secondary scale (hsl)
    for step, amount in ACCENT_STOPS.items():
        tokens.append(("--c-secondary-%d" % step, hsl_triple(ramp(highlight, amount))))
    tokens += [
        ("--c-bg-secondary", rgb_to_hex(highlight, "#")),
        ("--c-bg-secondary--pressed", rgb_to_hex(darken(highlight, 0.14), "#")),
        ("--c-fg-secondary", rgb_to_hex(highlight, "#")),
        ("--c-border-secondary", rgb_to_hex(highlight, "#")),
    ]

    # ui and editor font via caido's own font tokens; icon glyphs carry font-family:"Material Icons"
    # on their own elements, so overriding the text tokens leaves them untouched
    tokens += [
        ("--c-font-family-base", FONT_STACK),
        ("--c-font-family-mono", FONT_STACK),
    ]

    # :root:root outweighs caido's own :root so the override wins regardless of load order
    body = ":root:root{%s}\n" % "".join("%s:%s;" % kv for kv in tokens)
    # belt and suspenders for codemirror editors in case they set a literal family, not the token
    body += ".cm-editor,.cm-scroller,.cm-content,.cm-gutters{font-family:%s}\n" % FONT_STACK
    write_atomic(OUT, "/* generated by generate-caido-theme.py */\n" + body)

    sheet = evenbetter_stylesheet()
    if sheet is not None:
        inject(sheet, "%s\n%s%s\n" % (MARK_START, body, MARK_END))
    return 0


if __name__ == "__main__":
    sys.exit(main())
