#!/usr/bin/env bash
# current, hourly and daily forecast in one request, sanitised for Weather.qml
set -uo pipefail

TOGGLES="${QS_DOTFILES_DIR:-$HOME/projects/arch-dotfiles}/toggles"
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
URL+="&timezone=auto&forecast_days=4&forecast_hours=24"

RAW=$(curl -s --max-time 12 "$URL" 2>/dev/null || true)

if [[ -z "$RAW" ]]; then
    # stale-if-error
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

# windy is not a wmo code, beaufort 6
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
    # hour only, never the full timestamp
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
    # how the location was found, not where
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

# fail loudly if a location field leaks
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
