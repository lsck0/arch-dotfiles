#!/usr/bin/env bash
# One-line current-conditions string for the hyprlock screen
# (configs/hyprland/hyprlock.conf), polled every few minutes via
# cmd[update:...].
#
# Deliberately reads the ALREADY-SANITISED cache that
# plugins/bar/widgets/weather-fetch.sh writes
# (~/.cache/quickshell-weather.json), rather than calling Open-Meteo again
# from here. Two reasons:
#   1. No second network path to audit for the same "don't leak location"
#      guarantee weather-fetch.sh already enforces (banned-field scan on
#      every write) — this script only ever reads numbers, so it can't leak
#      what it never receives.
#   2. hyprlock's own poll cadence (this script, every few minutes) would
#      otherwise re-hit the API on a completely separate schedule from the
#      bar widget's 30-minute Process timer.
#
# If the cache doesn't exist yet (bar widget never ran) or is unreadable,
# print nothing — the label just doesn't render, same "degrade over
# disappearing only when there's truly nothing" rule as the bar widget.
set -euo pipefail

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell-weather.json"
[[ -r "$CACHE" ]] || exit 0

python3 - "$CACHE" <<'PY'
import json, sys

try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)

if not d.get("ok"):
    sys.exit(0)

c = d.get("current") or {}
units = (d.get("units") or {}).get("temp", "°C")


# Same verified WMO code -> glyph map as
# plugins/bar/widgets/Weather.qml's iconFor() — kept in sync deliberately,
# not re-derived, since that map already burned a cycle catching a wrong
# guessed codepoint (see Weather.qml's own header comment).
#
# All codepoints here are >U+FFFF (Supplementary Private Use Area-A,
# 0xF0000-0xFFFFD) — Python's \u escape takes EXACTLY 4 hex digits, so
# "\uf0599" silently parsed as \uf059 + literal "9" rather than erroring.
# Caught by screenshot verification: it rendered as an unrelated glyph
# (bell) plus a stray digit, not a missing-glyph tofu box, so it looked
# plausible at a glance. \U + 8 hex digits is required for this range.
def icon_for(code, is_day):
    c = code
    day = 1 if is_day is None else is_day
    if c == 0:
        return "\U000f0599" if day else "\U000f0594"
    if c in (1, 2):
        return "\U000f0595" if day else "\U000f0f31"
    if c == 3:
        return "\U000f0590"
    if c in (45, 48):
        return "\U000f0591"
    if 51 <= c <= 57:
        return "\U000f0597"
    if 61 <= c <= 65:
        return "\U000f0596"
    if c in (66, 67):
        return "\U000f067f"
    if 71 <= c <= 77:
        return "\U000f0598"
    if 80 <= c <= 82:
        return "\U000f0596"
    if c in (85, 86):
        return "\U000f0598"
    if c == 95:
        return "\U000f067e"
    if c in (96, 99):
        return "\U000f0592"
    return "\U000f0590"


try:
    code = int(c.get("code", 0) or 0)
except Exception:
    code = 0
is_day = c.get("isDay", 1)
glyph = icon_for(code, is_day)
temp = c.get("temp")
humidity = c.get("humidity")

if temp is None:
    sys.exit(0)

stale = " (stale)" if d.get("stale") else ""
print(f"{glyph}  {temp:.0f}{units}  ·  {humidity:.0f}% hum{stale}")
PY
