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
# Source: RainViewer's free public API (no key, no account). Its
# lat/lon-centred endpoint returns one ready-made square per frame, so this
# needs no tile-mosaic arithmetic:
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
# Twelve frames at ten-minute steps is two hours of history. More frames is
# more download for a loop nobody watches to the end.
FRAMES=12
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

INDEX=$(curl -s --max-time 12 "https://api.rainviewer.com/public/weather-maps.json" 2>/dev/null || true)
[[ -z "$INDEX" ]] && fail "offline"

mkdir -p "$CACHE_DIR" || fail "cache unavailable"

# Emit the frames to fetch as "<index> <unix-ts> <url-path>" lines.
PLAN=$(python3 - "$INDEX" "$FRAMES" <<'PY'
import json, sys
try:
    d = json.loads(sys.argv[1])
except Exception:
    sys.exit(1)
want = int(sys.argv[2])
radar = d.get("radar") or {}
# Nowcast frames are appended so the loop runs past "now" into the forecast
# when the provider has one; they are flagged in the manifest so the UI can
# say which part of the loop is a prediction.
frames = [(f, False) for f in (radar.get("past") or [])] + \
         [(f, True) for f in (radar.get("nowcast") or [])]
if not frames:
    sys.exit(1)
frames = frames[-want:]
print(d.get("host", "https://tilecache.rainviewer.com"))
for i, (f, is_forecast) in enumerate(frames):
    print(i, f.get("time", 0), f.get("path", ""), int(is_forecast))
PY
) || fail "bad index"

HOST=$(head -1 <<<"$PLAN")
export HOST SIZE ZOOM LAT LON COLOUR OPTIONS
[[ -z "$HOST" ]] && fail "bad index"

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

# DOWNLOADED IN PARALLEL. Twelve frames fetched one after another is twelve
# round trips end to end — the single biggest reason a cold radar took as long
# as it did. They are independent files from one CDN, so there is no ordering to
# preserve; -P 6 keeps it civil while cutting the wall time to roughly the
# slowest frame rather than the sum of all of them.
while read -r idx ts path is_forecast; do
    [[ -z "${path:-}" ]] && continue
    printf '%s\t%s\t%s\t%s\n' "$idx" "$ts" "$path" "$is_forecast"
done < <(tail -n +2 <<<"$PLAN") > "$STAGE/.plan"

# shellcheck disable=SC2016
< "$STAGE/.plan" cut -f1,3 | xargs -P 6 -n 2 bash -c '
    out=$(printf "%s/frame-%02d.png" "$STAGE" "$0")
    url="${HOST}${1}/${SIZE}/${ZOOM}/${LAT}/${LON}/${COLOUR}/${OPTIONS}.png"
    curl -sf --max-time 15 -o "$out" "$url" 2>/dev/null || exit 0
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
python3 - "$NOW" "$ZOOM" "$SIZE" "$MANIFEST" "$LIST" "$LAT" <<'PY' || PUBLISHED=0
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
    # Attribution is a licence condition of the free RainViewer API, so the
    # widget must actually display it.
    "attribution": "RainViewer",
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
# published. Superseded generations are dead weight — twelve 512px PNGs each —
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
