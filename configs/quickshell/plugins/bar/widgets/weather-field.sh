#!/usr/bin/env bash
# wind/pressure grid over the radar square, in image coordinates
set -uo pipefail

TOGGLES="${QS_DOTFILES_DIR:-$HOME/projects/arch-dotfiles}/toggles"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/weather-field.json"

# extent comes from the radar manifest
RADAR_MANIFEST="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/radar/manifest.json"
GRID=5
MAX_AGE=540

fail() { printf '{"ok":false,"error":"%s"}\n' "$1"; exit 0; }

mkdir -p "$(dirname "$CACHE")" 2>/dev/null || fail "cache unavailable"

if [[ -s "$CACHE" ]]; then
    age=$(( $(date +%s) - $(stat -c %Y "$CACHE" 2>/dev/null || echo 0) ))
    if (( age >= 0 && age < MAX_AGE )); then
        cat "$CACHE"
        exit 0
    fi
fi

read -r SOURCE COORDS <<<"$("$TOGGLES/toggle-weather-location.sh" resolve 2>/dev/null || echo none)"
[[ "$SOURCE" == "none" || -z "${COORDS:-}" ]] && fail "no location"
LAT=${COORDS%%,*}
LON=${COORDS##*,}

[[ -s "$RADAR_MANIFEST" ]] || fail "no radar"
SPAN_KM=$(python3 - "$RADAR_MANIFEST" <<'PY' 2>/dev/null
import json, sys
try:
    print(int(json.load(open(sys.argv[1])).get('spanKm') or 0))
except Exception:
    print(0)
PY
)
[[ "${SPAN_KM:-0}" -gt 0 ]] || fail "no radar extent"

# raw coordinates never leave this process
python3 - "$LAT" "$LON" "$SPAN_KM" "$GRID" "$CACHE" <<'PY'
import json, math, sys, urllib.parse, urllib.request

lat0, lon0 = float(sys.argv[1]), float(sys.argv[2])
span_km, grid, cache = int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]

half_m = span_km * 1000.0 / 2.0

# longitude degrees shrink with latitude
dlat = half_m / 111320.0
dlon = half_m / (111320.0 * max(0.15, math.cos(math.radians(lat0))))

points = []          # (u, v, lat, lon), u,v 0..1 from top-left
for row in range(grid):
    for col in range(grid):
        u = col / (grid - 1.0)
        v = row / (grid - 1.0)
        points.append((u, v,
                       lat0 + dlat * (1.0 - 2.0 * v),
                       lon0 + dlon * (2.0 * u - 1.0)))

query = urllib.parse.urlencode({
    "latitude": ",".join("%.4f" % p[2] for p in points),
    "longitude": ",".join("%.4f" % p[3] for p in points),
    # msl, surface pressure would contour the terrain
    "current": "wind_speed_10m,wind_direction_10m,pressure_msl",
    "timezone": "auto",
})

try:
    with urllib.request.urlopen(
            "https://api.open-meteo.com/v1/forecast?" + query, timeout=20) as response:
        payload = json.loads(response.read().decode())
except Exception:
    print('{"ok":false,"error":"offline"}')
    raise SystemExit

# one coordinate yields an object, not a list
if isinstance(payload, dict):
    payload = [payload]
if not isinstance(payload, list) or len(payload) != len(points):
    print('{"ok":false,"error":"unexpected response"}')
    raise SystemExit

cells = []
pressures = []
for (u, v, _lat, _lon), entry in zip(points, payload):
    current = (entry or {}).get("current") or {}
    speed = current.get("wind_speed_10m")
    direction = current.get("wind_direction_10m")
    pressure = current.get("pressure_msl")
    if speed is None or direction is None:
        continue
    cell = {
        "u": round(u, 4),
        "v": round(v, 4),
        "wind": round(float(speed), 1),
        # direction the wind comes from
        "dir": int(round(float(direction))) % 360,
    }
    if pressure is not None:
        cell["hpa"] = round(float(pressure), 1)
        pressures.append(cell["hpa"])
    cells.append(cell)

if not cells:
    print('{"ok":false,"error":"no data"}')
    raise SystemExit

units = (payload[0].get("current_units") or {}) if payload else {}

out = {
    "ok": True,
    "grid": grid,
    "cells": cells,
    "windUnits": units.get("wind_speed_10m", "km/h"),
    "pressureUnits": units.get("pressure_msl", "hPa"),
}
if pressures:
    out["pressureMin"] = round(min(pressures), 1)
    out["pressureMax"] = round(max(pressures), 1)

# fail loudly if a location field leaks
BANNED = {"latitude", "longitude", "lat", "lon", "elevation", "timezone",
          "timezone_abbreviation", "location", "place"}
def scan(node, path=""):
    if isinstance(node, dict):
        for key, value in node.items():
            if key.lower() in BANNED:
                return path + "." + key
            found = scan(value, path + "." + key)
            if found:
                return found
    elif isinstance(node, list):
        for index, value in enumerate(node):
            found = scan(value, "%s[%d]" % (path, index))
            if found:
                return found
    return None

leak = scan(out)
if leak:
    print(json.dumps({"ok": False, "error": "location field leaked: " + leak}))
    raise SystemExit

try:
    with open(cache, "w") as handle:
        json.dump(out, handle)
except Exception:
    pass

print(json.dumps(out))
PY
