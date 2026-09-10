#!/usr/bin/env bash
# Fetches the three tiers the SPEC asks for (current, 24h hourly, 3-day) in
# ONE Open-Meteo request, and re-emits a sanitised subset for Weather.qml.
#
# The sanitising is the point, not a formality. Open-Meteo's response echoes
# back `latitude`, `longitude`, `timezone`, `timezone_abbreviation` and
# `elevation`, and the API can also return `sunrise`/`sunset` — every one of
# which identifies where the user is. The SPEC says the widget must "use the
# current location but NOT REVEAL IT".
#
# Rather than asking QML to remember never to bind those, they are dropped
# here: the JSON that reaches the widget contains only whitelisted numeric
# fields, so no future edit to the QML can leak a location that was never
# handed to it. That is a structural guarantee instead of a discipline one.
#
# Deliberately NOT requested at all: sunrise, sunset, daylight_duration.
# Sunrise time plus a date pins latitude, and the clock offset gives
# longitude — it is the sharpest geolocation oracle in the whole API.
# UV is fetched for *current* only, never hourly, for the same reason: a
# full-day UV curve peaks at local solar noon, which is the same oracle in
# slower motion.
set -uo pipefail

TOGGLES="$HOME/projects/arch-dotfiles/toggles"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell-weather.json"

fail() { printf '{"ok":false,"error":"%s"}\n' "$1"; exit 0; }

read -r SOURCE COORDS <<<"$("$TOGGLES/toggle-weather-location.sh" resolve 2>/dev/null || echo none)"
[[ "$SOURCE" == "none" || -z "${COORDS:-}" ]] && fail "no location"

LAT=${COORDS%%,*}
LON=${COORDS##*,}

URL="https://api.open-meteo.com/v1/forecast?latitude=${LAT}&longitude=${LON}"
URL+="&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,is_day,precipitation,cloud_cover,wind_speed_10m,wind_direction_10m,wind_gusts_10m,uv_index,surface_pressure"
URL+="&hourly=temperature_2m,relative_humidity_2m,precipitation,precipitation_probability,weather_code"
URL+="&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,wind_speed_10m_max,uv_index_max"
# timezone=auto is resolved server-side from coordinates it already has, so
# it discloses nothing extra — but the resolved name never reaches the UI.
# Fetch four calendar days so the UI can omit today and still show three
# complete forecast rows starting tomorrow.
URL+="&timezone=auto&forecast_days=4&forecast_hours=24"

RAW=$(curl -s --max-time 12 "$URL" 2>/dev/null || true)

if [[ -z "$RAW" ]]; then
    # Stale-if-error: a cached reading beats an empty panel, and the widget
    # is told the data is stale so it can say so.
    if [[ -s "$CACHE" ]]; then
        python3 -c "
import json,sys
d=json.load(open('$CACHE')); d['stale']=True; print(json.dumps(d))" 2>/dev/null && exit 0
    fi
    fail "offline"
fi

python3 - "$RAW" "$SOURCE" "$CACHE" <<'PY'
import json, sys, datetime

raw, source, cache = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    d = json.loads(raw)
except Exception:
    print('{"ok":false,"error":"bad response"}'); sys.exit(0)

if "current" not in d or "daily" not in d:
    msg = d.get("reason", "unexpected response")
    print(json.dumps({"ok": False, "error": str(msg)[:120]})); sys.exit(0)

c = d["current"]
hr = d.get("hourly", {})
dy = d["daily"]

# "Windy" is NOT a WMO weather code — the enum only covers
# clear/cloud/fog/drizzle/rain/snow/thunderstorm. The SPEC's three-way
# "sunny, rain, windy" summary therefore has to be derived: take the code
# for the sunny/rain axis, then override to windy above a threshold.
# Beaufort 6 ("strong breeze") = 39 km/h, chosen because it is a real
# scale boundary rather than a round number picked by feel.
WINDY_KMH = 39.0

def g(src, key, i=None, default=None):
    v = src.get(key)
    if v is None: return default
    if i is not None:
        if not isinstance(v, list) or i >= len(v): return default
        v = v[i]
    return default if v is None else v

hours = []
times = hr.get("time", []) or []
for i in range(len(times)):
    # Only the hour-of-day is emitted, never the date or the full timestamp.
    # The hour is already visible on the user's own bar clock, so it adds
    # nothing a screenshot did not already show.
    try:
        hh = datetime.datetime.fromisoformat(times[i]).strftime("%H")
    except Exception:
        continue
    hours.append({
        "h":        hh,
        "temp":     g(hr, "temperature_2m", i, 0),
        "humidity": g(hr, "relative_humidity_2m", i, 0),
        "precip":   g(hr, "precipitation", i, 0),
        "pop":      g(hr, "precipitation_probability", i, 0),
        "code":     g(hr, "weather_code", i, 0),
    })

days = []
dtimes = dy.get("time", []) or []
today = datetime.date.today()
for i in range(len(dtimes)):
    try:
        dt = datetime.date.fromisoformat(dtimes[i])
        delta = (dt - today).days
        label = "Today" if delta == 0 else ("Tomorrow" if delta == 1 else dt.strftime("%a"))
    except Exception:
        label = "?"
    wind_max = g(dy, "wind_speed_10m_max", i, 0)
    days.append({
        "label":   label,
        "code":    g(dy, "weather_code", i, 0),
        "hi":      g(dy, "temperature_2m_max", i, 0),
        "lo":      g(dy, "temperature_2m_min", i, 0),
        "precip":  g(dy, "precipitation_sum", i, 0),
        "pop":     g(dy, "precipitation_probability_max", i, 0),
        "windMax": wind_max,
        "uvMax":   g(dy, "uv_index_max", i, 0),
        "windy":   bool(wind_max and wind_max >= WINDY_KMH),
    })

out = {
    "ok": True,
    # How the location was determined — NOT where it is. Lets the panel be
    # honest about "this is a timezone-wide guess" without naming a place.
    "source": source,
    "stale": False,
    "current": {
        "temp":      g(c, "temperature_2m", None, 0),
        "feelsLike": g(c, "apparent_temperature", None, 0),
        "humidity":  g(c, "relative_humidity_2m", None, 0),
        "code":      g(c, "weather_code", None, 0),
        "isDay":     g(c, "is_day", None, 1),
        "precip":    g(c, "precipitation", None, 0),
        "cloud":     g(c, "cloud_cover", None, 0),
        "wind":      g(c, "wind_speed_10m", None, 0),
        "windDir":   g(c, "wind_direction_10m", None, 0),
        "gust":      g(c, "wind_gusts_10m", None, 0),
        "uv":        g(c, "uv_index", None, 0),
        "pressure":  g(c, "surface_pressure", None, 0),
    },
    "units": {
        "temp":  (d.get("current_units", {}) or {}).get("temperature_2m", "°C"),
        "wind":  (d.get("current_units", {}) or {}).get("wind_speed_10m", "km/h"),
        "precip": (d.get("current_units", {}) or {}).get("precipitation", "mm"),
    },
    "hourly": hours,
    "daily": days,
}

# Assert the whitelist actually held, rather than trusting that it did.
# If a location-bearing key ever reaches this point, emit an error instead
# of leaking it — a loud failure beats a quiet disclosure.
BANNED = {"latitude", "longitude", "timezone", "timezone_abbreviation",
          "elevation", "sunrise", "sunset", "daylight_duration",
          "nearest_area", "location"}
def scan(o, path=""):
    if isinstance(o, dict):
        for k, v in o.items():
            if k in BANNED: return f"{path}.{k}"
            r = scan(v, f"{path}.{k}")
            if r: return r
    elif isinstance(o, list):
        for i, v in enumerate(o):
            r = scan(v, f"{path}[{i}]")
            if r: return r
    return None

leak = scan(out)
if leak:
    print(json.dumps({"ok": False, "error": "location field leaked: " + leak}))
    sys.exit(0)

try:
    with open(cache, "w") as f: json.dump(out, f)
except Exception:
    pass

print(json.dumps(out))
PY
