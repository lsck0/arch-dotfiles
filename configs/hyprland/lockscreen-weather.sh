#!/usr/bin/env bash

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
print(f"{glyph}  {temp:.0f}{units}  {humidity:.0f}% hum{stale}")
PY
