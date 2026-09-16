#!/usr/bin/env bash
# Downloads a short precipitation-radar loop centred on the current location
# and prints a manifest of LOCAL FILE PATHS for Weather.qml to animate.
#
# WHY IT DOWNLOADS INSTEAD OF HANDING QML A URL. Every radar URL carries the
# centre coordinate in its path. If the widget loaded the URL itself, the
# location would be in the QML — the exact thing weather-fetch.sh's whitelist
# exists to prevent, reintroduced through a different door. The frames are
# fetched here and the widget is given file paths and relative timestamps, so
# the same structural guarantee holds for radar as for the forecast.
#
# NO BASEMAP, DELIBERATELY. RainViewer serves transparent overlays; the usual
# treatment is to composite them over a street map. That would draw the user's
# own town under the rain — a screenshot of this panel would reveal the
# location outright, which is precisely what the SPEC forbids. The loop is
# shown over a flat surface with a centre marker instead: you can read where
# the rain is relative to you without the image saying where "you" is.
#
# Sources, both keyless:
#   DWD GeoServer WMS (Germany and surroundings): keeps three days of 5-minute
#   RV composites, so it can serve the full four hours of history.
#   RainViewer's public API everywhere else: its index only lists the last two
#   hours and older frame paths return 410, so the loop is shorter there.
#   {host}{path}/{size}/{z}/{lat}/{lon}/{colour}/{smooth}_{snow}.png
set -uo pipefail

TOGGLES="${QS_DOTFILES_DIR:-$HOME/projects/arch-dotfiles}/toggles"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/radar"
MANIFEST="$CACHE_DIR/manifest.json"

# z=7 is roughly a 400 km square at mid latitudes: wide enough to see weather
# arriving, tight enough that a front is not one undifferentiated smear.
ZOOM=7
SIZE=512
# 4 = the "Universal Blue" palette; 1_1 = smoothed, snow shown separately.
COLOUR=4
OPTIONS=1_1
# Four hours of history at ten-minute steps.
HISTORY_MIN=240
STEP_MIN=10
# The upstream index only advances every ten minutes, so refetching sooner
# re-downloads identical PNGs.
MAX_AGE=540

fail() { printf '{"ok":false,"error":"%s"}\n' "$1"; exit 0; }

# Serve the cached manifest when it is still current. Weather.qml refreshes on
# hover, and hovering the widget five times in a minute must not mean sixty
# image downloads.
if [[ -s "$MANIFEST" ]]; then
    age=$(( $(date +%s) - $(stat -c %Y "$MANIFEST" 2>/dev/null || echo 0) ))
    if (( age >= 0 && age < MAX_AGE )); then
        cat "$MANIFEST"
        exit 0
    fi
fi

read -r SOURCE COORDS <<<"$("$TOGGLES/toggle-weather-location.sh" resolve 2>/dev/null || echo none)"
[[ "$SOURCE" == "none" || -z "${COORDS:-}" ]] && fail "no location"
LAT=${COORDS%%,*}
LON=${COORDS##*,}

# Inside the DWD composite the WMS is used; it needs no index round trip.
if python3 -c "import sys; la, lo = map(float, sys.argv[1:3]); sys.exit(not (47.0 <= la <= 55.1 and 5.8 <= lo <= 15.1))" "$LAT" "$LON"; then
    PROVIDER=dwd
    INDEX=""
    ATTRIBUTION="Deutscher Wetterdienst"
else
    PROVIDER=rainviewer
    INDEX=$(curl -s --max-time 12 "https://api.rainviewer.com/public/weather-maps.json" 2>/dev/null || true)
    [[ -z "$INDEX" ]] && fail "offline"
    ATTRIBUTION="RainViewer"
fi

mkdir -p "$CACHE_DIR" || fail "cache unavailable"

# Emit the frames to fetch as "<index> <unix-ts> <url> <is-forecast>" lines.
# Both providers are framed on the same web-mercator square (zoom, size and
# centre), so spanKm and the wind field overlay stay aligned whichever serves.
PLAN=$(python3 - "$PROVIDER" "$INDEX" "$HISTORY_MIN" "$STEP_MIN" "$SIZE" "$ZOOM" "$LAT" "$LON" "$COLOUR" "$OPTIONS" <<'PY'
import json, math, sys, time, urllib.parse
provider, index = sys.argv[1], sys.argv[2]
history, step, size, zoom = (int(a) for a in sys.argv[3:7])
lat, lon = float(sys.argv[7]), float(sys.argv[8])
colour, options = sys.argv[9], sys.argv[10]

if provider == "dwd":
    r = 6378137.0
    x = math.radians(lon) * r
    y = math.log(math.tan(math.pi / 4 + math.radians(lat) / 2)) * r
    half = size * 156543.03392 / 2 ** zoom / 2
    # The newest composite lands a few minutes after its timestamp.
    latest = (int(time.time()) - 5 * 60) // (step * 60) * (step * 60)
    for i, ts in enumerate(range(latest - history * 60, latest + 1, step * 60)):
        query = urllib.parse.urlencode({
            "service": "WMS", "version": "1.1.1", "request": "GetMap",
            "layers": "dwd:Radar_rv_product_1x1km_ger", "styles": "",
            "srs": "EPSG:3857", "bbox": "%f,%f,%f,%f" % (x - half, y - half, x + half, y + half),
            "width": size, "height": size, "format": "image/png", "transparent": "true",
            "time": time.strftime("%Y-%m-%dT%H:%M:00.000Z", time.gmtime(ts)),
        })
        print(i, ts, "https://maps.dwd.de/geoserver/dwd/wms?" + query, 0)
    sys.exit(0)

try:
    d = json.loads(index)
except Exception:
    sys.exit(1)
radar = d.get("radar") or {}
# Nowcast frames are appended so the loop runs past "now" into the forecast
# when the provider has one; they are flagged in the manifest so the UI can
# say which part of the loop is a prediction.
frames = [(f, False) for f in (radar.get("past") or [])] + \
         [(f, True) for f in (radar.get("nowcast") or [])]
if not frames:
    sys.exit(1)
frames = frames[-(history // step + 1):]
host = d.get("host", "https://tilecache.rainviewer.com")
for i, (f, is_forecast) in enumerate(frames):
    url = "%s%s/%d/%d/%s/%s/%s/%s.png" % (host, f.get("path", ""), size, zoom, lat, lon, colour, options)
    print(i, f.get("time", 0), url, int(is_forecast))
PY
) || fail "bad index"
[[ -z "$PLAN" ]] && fail "bad index"

# EACH REFRESH GETS ITS OWN FRAME DIRECTORY, AND THE MANIFEST IS THE SWITCH.
#
# The first version deleted every frame before downloading the new ones, so for
# the length of a refresh the cache held nothing and a panel opened in that
# window showed "Loading radar…" over a loop that had been perfectly good a
# second earlier.
#
# Staging into a scratch dir and then moving the files into the live directory
# did not actually fix that: the move still had to `rm` the old frames first,
# because the live paths are the same on every run. The window shrank from
# "the whole download" to "the length of an rm plus twelve renames", but a
# reader landing inside it still saw a half-populated loop, and the manifest
# pointed at files that were being deleted underneath it.
#
# So the frames are never overwritten at all. Every run writes to a directory
# named after its own timestamp, and the manifest — renamed into place, which
# IS atomic on one filesystem — is what decides which generation is live. A
# reader either sees the whole previous loop or the whole new one. Superseded
# generations are removed only after the manifest no longer names them.
NOW=$(date +%s)

STAGE="$CACHE_DIR/f-$NOW"
export STAGE
rm -rf "$STAGE"
mkdir -p "$STAGE" || fail "cache unavailable"

# DOWNLOADED IN PARALLEL. Two dozen frames fetched one after another is as many
# round trips end to end — the single biggest reason a cold radar took as long
# as it did. They are independent files from one CDN, so there is no ordering to
# preserve; -P 6 keeps it civil while cutting the wall time to roughly the
# slowest frame rather than the sum of all of them.
while read -r idx ts path is_forecast; do
    [[ -z "${path:-}" ]] && continue
    printf '%s\t%s\t%s\t%s\n' "$idx" "$ts" "$path" "$is_forecast"
done <<<"$PLAN" > "$STAGE/.plan"

# shellcheck disable=SC2016
< "$STAGE/.plan" cut -f1,3 | xargs -P 6 -n 2 bash -c '
    out=$(printf "%s/frame-%02d.png" "$STAGE" "$0")
    curl -sf --max-time 15 -o "$out" "$1" 2>/dev/null || exit 0
    # A truncated body or an error page is not a usable frame; drop it rather
    # than letting the widget render a hole in the middle of the loop.
    [[ -s "$out" ]] || { rm -f "$out"; exit 0; }
    head -c 8 "$out" | grep -q PNG || rm -f "$out"
' 2>/dev/null

# The frames stay where they were downloaded, so the paths in the manifest are
# the staging paths. Nothing is moved and nothing is deleted yet.
ENTRIES=""
while IFS=$'\t' read -r idx ts path is_forecast; do
    staged=$(printf '%s/frame-%02d.png' "$STAGE" "$idx")
    [[ -s "$staged" ]] || continue
    ENTRIES+="$staged $ts $is_forecast"$'\n'
done < "$STAGE/.plan"

[[ -z "$ENTRIES" ]] && { rm -rf "$STAGE"; fail "no frames"; }

LIST="$STAGE/.frames"
printf '%s' "$ENTRIES" > "$LIST"

# The manifest is what reaches QML, and it carries no coordinate: file paths,
# minutes relative to now, and the span the image covers in kilometres. The
# km span is computed here from the zoom and the latitude, because deriving it
# in the widget would mean handing the widget the latitude.
#
# `|| PUBLISHED=0` rather than `|| true`: the exit status says whether the
# manifest actually got renamed into place, and that is the one thing that
# decides whether the older frame directories are safe to remove.
PUBLISHED=1
python3 - "$NOW" "$ZOOM" "$SIZE" "$MANIFEST" "$LIST" "$LAT" "$ATTRIBUTION" <<'PY' || PUBLISHED=0
import json, os, sys, math

now, zoom, size, manifest, listfile, lat = (
    int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]),
    sys.argv[4], sys.argv[5], float(sys.argv[6]))

frames = []
for line in open(listfile):
    parts = line.split()
    if len(parts) < 3:
        continue
    path, ts, is_forecast = parts[0], int(parts[1]), parts[2] == "1"
    frames.append({
        "file": path,
        # Relative, never absolute: a wall-clock timestamp plus a screenshot
        # narrows a timezone, and the bar clock already shows local time.
        "minutes": int(round((ts - now) / 60.0)),
        "forecast": is_forecast,
    })

# Web-Mercator ground resolution at this latitude, times the image edge.
metres_per_px = 156543.03392 * math.cos(math.radians(lat)) / (2 ** zoom)
span_km = int(round(size * metres_per_px / 1000.0))

out = {
    "ok": True,
    "frames": frames,
    "spanKm": span_km,
    # Attribution is a licence condition of both free sources, so the widget
    # must actually display it.
    "attribution": sys.argv[7],
}

BANNED = {"lat", "lon", "latitude", "longitude", "coords", "place", "area"}
def scan(o, path=""):
    if isinstance(o, dict):
        for k, v in o.items():
            if k.lower() in BANNED:
                return path + "." + k
            r = scan(v, path + "." + k)
            if r: return r
    elif isinstance(o, list):
        for i, v in enumerate(o):
            r = scan(v, "%s[%d]" % (path, i))
            if r: return r
    return None

leak = scan(out)
if leak:
    print(json.dumps({"ok": False, "error": "location field leaked: " + leak}))
    # Non-zero, so the caller does NOT prune: no manifest was written, the
    # previous generation is still the live one, and deleting it here would
    # strand the manifest that still names it.
    sys.exit(1)

# Written beside the manifest and renamed over it. os.replace is atomic within
# a filesystem, so a concurrent reader (`cat "$MANIFEST"` on the cached path,
# which is what most calls do) gets either the whole previous manifest or the
# whole new one — never a half-written object, and never one naming frames that
# are mid-delete. The rename is also what publishes this run's frame directory;
# the exit status tells the shell whether the generation is safe to prune.
ok = True
try:
    tmp = manifest + ".tmp"
    with open(tmp, "w") as f:
        json.dump(out, f)
    os.replace(tmp, manifest)
except Exception:
    ok = False
    try:
        os.unlink(manifest + ".tmp")
    except Exception:
        pass

print(json.dumps(out))
sys.exit(0 if ok else 1)
PY

# PRUNE ONLY WHAT THE MANIFEST NO LONGER NAMES, and only once it has been
# published. Superseded generations are dead weight — two dozen 512px PNGs each —
# but a reader that loaded the old manifest a moment ago is still displaying
# them, so this runs last and never touches the generation that just went live.
#
# The `frame-*.png` sweep clears the flat layout the earlier version wrote
# straight into the cache directory, so an upgrade does not leave one dead loop
# behind forever.
if (( PUBLISHED )); then
    for old in "$CACHE_DIR"/f-*; do
        [[ -d "$old" ]] || continue
        [[ "$old" == "$STAGE" ]] && continue
        rm -rf "$old"
    done
    rm -f "$CACHE_DIR"/frame-*.png "$CACHE_DIR"/.frames
else
    # Nothing published, so this run's frames are unreachable. Drop them rather
    # than accumulating a directory per failed refresh.
    rm -rf "$STAGE"
fi
