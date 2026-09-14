"""Shared wallpaper-palette conditioning.

The same maths was about to exist in three places: quickshell's
`configs/quickshell/Commons/Color.qml` (QML, unavoidably separate — it has to
run inside the shell), `generate-oomox-colors.py` for GTK, and
`generate-hermes-skin.py` for the Hermes agent. Two of those are Python, so
they share this instead of carrying a third and fourth copy of WCAG luminance.

The QML copy stays duplicated on purpose: importing Python into the shell is
not an option, and the alternative — the shell shelling out to a script on
every palette change — would put a process spawn in the wallpaper crossfade
path. The two are kept deliberately in step, and the constants below are the
same ones Theme.qml defaults to.

WHY ANY OF THIS EXISTS. pywal/wallust report whatever the wallpaper contains.
Some wallpapers are a bad basis for a UI: a bright one yields a background too
light to read on, a washed-out one yields an accent with no presence, and a
fixed slot-to-role mapping can pair a near-black foreground with a mid-tone
background (which is exactly the bug that made nemo unreadable). Conditioning
the palette rather than trusting it is what makes any wallpaper safe.
"""

# WCAG AA for body text. Everything that has text drawn on it is held to this.
TEXT_RATIO = 4.5

# The value band a background is forced into. Matches Theme.qml's
# backgroundValueMin/Max defaults so the shell and everything themed from here
# agree about how dark "dark" is.
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
    """Clamp value into a band, keeping hue and saturation.

    This is what stops a bright wallpaper producing an unreadable surface.
    """
    h, s, v = rgb_to_hsv(rgb)
    return hsv_to_rgb(h, s, max(lo, min(hi, v)))


def vivify(rgb, min_s, min_v):
    """Floor saturation/value so a washed-out wallpaper still yields an accent
    with presence rather than a grey smudge."""
    h, s, v = rgb_to_hsv(rgb)
    return hsv_to_rgb(h, max(min_s, s), max(min_v, v))


def lift(rgb, amount):
    """Raise a surface's value, so panels and controls separate from the
    window behind them instead of being pulled out of the photo."""
    h, s, v = rgb_to_hsv(rgb)
    return hsv_to_rgb(h, s * 0.9, min(1.0, v + amount))


def mix(a, b, t):
    return [a[i] * (1 - t) + b[i] * t for i in range(3)]


def readable_on(bg, preferred, ratio=TEXT_RATIO):
    """A foreground that actually clears `ratio` against `bg`.

    Starts from the palette's own foreground so the theme keeps its character,
    then walks toward whichever pole the background is furthest from. Falls
    back to that pole outright if the walk cannot get there: a guaranteed
    legible plain colour beats a tinted unreadable one.
    """
    white, black = (1.0, 1.0, 1.0), (0.0, 0.0, 0.0)
    target = white if luminance(bg) < 0.18 else black
    out = list(preferred)
    for _ in range(24):
        if contrast(out, bg) >= ratio:
            return out
        out = mix(out, target, 0.12)
    return list(target) if contrast(target, bg) >= contrast(out, bg) else out


def readable_light_on(bg, preferred, ratio=TEXT_RATIO):
    """Like `readable_on`, but only ever walks toward WHITE.

    Used where the polarity has to be fixed by design rather than discovered.
    A generic "make it readable" pass will happily answer with dark text on a
    mid-tone fill — which is 4.5:1 on paper and is precisely the "nearly black
    on a medium bright background" complaint that started all of this.
    """
    out = list(preferred)
    for _ in range(24):
        if contrast(out, bg) >= ratio:
            return out
        out = mix(out, (1.0, 1.0, 1.0), 0.12)
    return out


def dim_toward(fg, bg, ratio=2.6):
    """De-emphasised text: pulled TOWARD the background until it is dimmer.

    `readable_on(bg, fg, 2.4)` does not do this — it enforces a *floor*, so a
    foreground already at 10:1 comes back untouched and "dim" ends up
    identical to body text. De-emphasis needs a ceiling instead.
    """
    out = list(fg)
    for _ in range(40):
        if contrast(out, bg) <= ratio:
            return out
        out = mix(out, bg, 0.08)
    return out


# Canonical hues for the roles that carry MEANING rather than style, in the
# 0..1 hue space used here: red ~0, amber ~0.11, green ~0.33.
SEMANTIC_HUES = {"error": 0.0, "warn": 0.11, "ok": 0.33}


def semantic(role, reference, bg, ratio=TEXT_RATIO):
    """A success/warning/error colour that still means what it says.

    Deriving these from wallpaper slots the way ordinary accents are derived
    produces a blue "error" and a purple "ok" on any palette that happens to
    lack red and green — which is most of them. That is the same failure as
    assigning a foreground by palette index: the value passes every numeric
    check and communicates the wrong thing.

    So the HUE is pinned to the canonical one and only the saturation/value
    character is borrowed from `reference` (the wallpaper's accent), then the
    result is forced legible against `bg`. The palette still shapes how
    vivid/muted the colour is; it just cannot make green stop being green.
    """
    _, s, v = rgb_to_hsv(reference)
    h = SEMANTIC_HUES[role]
    s = max(0.45, min(0.85, s))
    v = max(0.55, v)
    out = hsv_to_rgb(h, s, v)
    for _ in range(24):
        if contrast(out, bg) >= ratio:
            return out
        # Lift value first (keeps the hue readable); only then desaturate.
        _, s2, v2 = rgb_to_hsv(out)
        out = hsv_to_rgb(h, max(0.35, s2 * 0.96), min(1.0, v2 * 1.07))
    return out


def selection_pair(accent, fg, ratio=TEXT_RATIO):
    """Selection background and foreground, decided TOGETHER.

    Deciding them separately is what breaks: pick the background from one
    palette slot and the foreground from another and you get whatever polarity
    falls out. The rule here is fixed — selections are always LIGHT text on a
    darkened accent, which is what essentially every desktop does. The
    accent's value is walked down until light text clears the ratio, keeping
    hue and saturation so it still reads as the wallpaper's accent.
    """
    h, s, v = rgb_to_hsv(accent)
    for _ in range(30):
        cand = hsv_to_rgb(h, s, v)
        light = readable_light_on(cand, fg, ratio)
        if contrast(light, cand) >= ratio:
            return cand, light
        v *= 0.92
    return hsv_to_rgb(h, s, v), [1.0, 1.0, 1.0]
