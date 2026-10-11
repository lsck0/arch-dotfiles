"""Shared palette conditioning; keep in step with quickshell Commons/Color.qml."""

import json
import os
import sys

WAL_COLORS_JSON = os.path.expanduser("~/.cache/wal/colors.json")

# wcag aa for body text
TEXT_RATIO = 4.5

BG_VALUE_MIN = 0.08
BG_VALUE_MAX = 0.26


def hex_to_rgb(value):
    v = str(value).lstrip("#")
    return tuple(int(v[i:i + 2], 16) / 255 for i in (0, 2, 4))


def rgb_to_hex(rgb, prefix=""):
    return prefix + "".join("%02X" % max(0, min(255, round(c * 255))) for c in rgb)


def rgb_to_hsv(rgb):
    r, g, b = rgb
    hi, lo = max(rgb), min(rgb)
    d = hi - lo
    if d == 0:
        h = 0.0
    elif hi == r:
        h = ((g - b) / d) % 6
    elif hi == g:
        h = (b - r) / d + 2
    else:
        h = (r - g) / d + 4
    return h / 6, (0.0 if hi == 0 else d / hi), hi


def hsv_to_rgb(h, s, v):
    i = int(h * 6) % 6
    f = h * 6 - int(h * 6)
    p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    return [(v, t, p), (q, v, p), (p, v, t),
            (p, q, v), (t, p, v), (v, p, q)][i]


def luminance(rgb):
    def ch(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def tone_map(rgb, lo=BG_VALUE_MIN, hi=BG_VALUE_MAX):
    """Clamp value into a band, keeping hue and saturation."""
    h, s, v = rgb_to_hsv(rgb)
    return hsv_to_rgb(h, s, max(lo, min(hi, v)))


def vivify(rgb, min_s, min_v):
    """Floor saturation and value."""
    h, s, v = rgb_to_hsv(rgb)
    return hsv_to_rgb(h, max(min_s, s), max(min_v, v))


def lift(rgb, amount):
    """Raise a surface's value."""
    h, s, v = rgb_to_hsv(rgb)
    return hsv_to_rgb(h, s * 0.9, min(1.0, v + amount))


def mix(a, b, t):
    return [a[i] * (1 - t) + b[i] * t for i in range(3)]


def readable_on(bg, preferred, ratio=TEXT_RATIO):
    """Walk `preferred` toward black or white until it clears `ratio`."""
    white, black = (1.0, 1.0, 1.0), (0.0, 0.0, 0.0)
    target = white if luminance(bg) < 0.18 else black
    out = list(preferred)
    for _ in range(24):
        if contrast(out, bg) >= ratio:
            return out
        out = mix(out, target, 0.12)
    return list(target) if contrast(target, bg) >= contrast(out, bg) else out


def readable_light_on(bg, preferred, ratio=TEXT_RATIO):
    """Like `readable_on`, but only walks toward white."""
    out = list(preferred)
    for _ in range(24):
        if contrast(out, bg) >= ratio:
            return out
        out = mix(out, (1.0, 1.0, 1.0), 0.12)
    return out


def dim_toward(fg, bg, ratio=2.6):
    """Pull `fg` toward `bg` until contrast is at most `ratio`."""
    out = list(fg)
    for _ in range(40):
        if contrast(out, bg) <= ratio:
            return out
        out = mix(out, bg, 0.08)
    return out


# red, amber, green in 0..1 hue space
SEMANTIC_HUES = {"error": 0.0, "warn": 0.11, "ok": 0.33}


def semantic(role, reference, bg, ratio=TEXT_RATIO):
    """Status colour with a pinned hue, borrowing s/v from `reference`."""
    _, s, v = rgb_to_hsv(reference)
    h = SEMANTIC_HUES[role]
    s = max(0.45, min(0.85, s))
    v = max(0.55, v)
    out = hsv_to_rgb(h, s, v)
    for _ in range(24):
        if contrast(out, bg) >= ratio:
            return out
        # lift value before desaturating
        _, s2, v2 = rgb_to_hsv(out)
        out = hsv_to_rgb(h, max(0.35, s2 * 0.96), min(1.0, v2 * 1.07))
    return out


def selection_pair(accent, fg, ratio=TEXT_RATIO):
    """Light text on a darkened accent, chosen together."""
    h, s, v = rgb_to_hsv(accent)
    for _ in range(30):
        cand = hsv_to_rgb(h, s, v)
        light = readable_light_on(cand, fg, ratio)
        if contrast(light, cand) >= ratio:
            return cand, light
        v *= 0.92
    return hsv_to_rgb(h, s, v), [1.0, 1.0, 1.0]


def wal_load(program):
    """Return slot(name, fallback) over wal's colors.json, or None after reporting why it is unreadable."""
    try:
        with open(WAL_COLORS_JSON) as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        print("%s: cannot read %s: %s" % (program, WAL_COLORS_JSON, exc), file=sys.stderr)
        return None
    special, colors = data.get("special", {}), data.get("colors", {})

    def slot(name, fallback):
        try:
            return hex_to_rgb(colors.get(name) or special.get(name) or fallback)
        except (ValueError, IndexError):
            return hex_to_rgb(fallback)

    return slot


def write_atomic(path, body):
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        fh.write(body)
    os.replace(tmp, path)
