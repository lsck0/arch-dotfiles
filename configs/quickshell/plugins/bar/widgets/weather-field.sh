#!/usr/bin/env bash
# A coarse grid of wind and surface pressure over the same square the radar loop covers, emitted in IMAGE COORDINATES so Weather.qml can draw a vector field and isobars on top of the radar without ever being told where it is.
set -uo pipefail

TOGGLES="${QS_DOTFILES_DIR:-$HOME/projects/arch-dotfiles}/toggles"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/weather-field.json"

# The extent comes from the RADAR MANIFEST, not from a copy of the radar's zoom and tile size.
RADAR_MANIFEST="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/radar/manifest.json"
GRID=5
MAX_AGE=540

fail() { printf '{"ok":false,"error":"%s"}\n' "$1"; exit 0; }

# Same reason as weather-alerts.sh: nothing guarantees ~/.cache/quickshell exists.
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

# No radar means nothing to overlay, and no extent to match.
[[ -s "$RADAR_MANIFEST" ]] || fail "no radar"
# Path as argv, not interpolated into the program text — see the same change in weather-alerts.sh.
SPAN_KM=$(python3 - "$RADAR_MANIFEST" <<'PY' 2>/dev/null
import json, sys
try:
    print(int(json.load(open(sys.argv[1])).get('spanKm') or 0))
except Exception:
    print(0)
PY
)
[[ "${SPAN_KM:-0}" -gt 0 ]] || fail "no radar extent"

# Build the grid, call the API, and reduce to image coordinates — all in one place so the raw coordinates never leave this process.
python3 - "$LAT" "$LON" "$SPAN_KM" "$GRID" "$CACHE" <<'PY'
import json, math, sys, urllib.parse, urllib.request

lat0, lon0 = float(sys.argv[1]), float(sys.argv[2])
span_km, grid, cache = int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]

# The radar image spans `span_km` edge to edge, so the grid reaches half that
# from the centre in each direction.
half_m = span_km * 1000.0 / 2.0

# Metres to degrees. Longitude degrees shrink with latitude, which matters at
# this span — ignoring it would skew the field sideways.
dlat = half_m / 111320.0
dlon = half_m / (111320.0 * max(0.15, math.cos(math.radians(lat0))))

points = []          # (u, v, lat, lon); u,v are 0..1 from the image's top-left
for row in range(grid):
    for col in range(grid):
        u = col / (grid - 1.0)
        v = row / (grid - 1.0)
        # v grows downward in image space, and latitude grows upward.
        points.append((u, v,
                       lat0 + dlat * (1.0 - 2.0 * v),
                       lon0 + dlon * (2.0 * u - 1.0)))

query = urllib.parse.urlencode({
    "latitude": ",".join("%.4f" % p[2] for p in points),
    "longitude": ",".join("%.4f" % p[3] for p in points),
    # pressure_msl, NOT surface_pressure. Surface pressure is station pressure
    # and falls ~12 hPa per 100 m of altitude, so contouring it draws the
    # terrain: the first run over this grid spanned 936-1024 hPa purely from
    # elevation. Mean-sea-level pressure is the field isobars are actually
    # defined on.
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

# One coordinate yields an object, several yield a list. Normalise.
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
        # Meteorological convention: the direction the wind comes FROM.
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

# Same assertion as the other two: a loud failure beats a quiet disclosure.
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
