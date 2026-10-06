#!/usr/bin/env python3
"""Weather data for Weather.qml, one JSON object per run on stdout.

    weather.py forecast   current conditions, 24 hourly and 4 daily slots (open-meteo)
    weather.py radar      {"radar": rain radar loop manifest, "field": wind/pressure grid over the same square}
    weather.py alerts     meteoalarm warnings around the location

Each reply (each half of radar) carries "ok"; a failed one carries "error" in place of data. Fresh replies come
from the cache under $XDG_CACHE_HOME/quickshell, so calling on every hover is cheap.

Location privacy: coordinates come from scripts/toggles/toggle-weather-location.sh and go only into the provider requests
that need them (open-meteo, the dwd wms bbox, rainviewer tile urls, nominatim at county zoom). No reply may name
the place: reply_publish checks every reply against LEAK_KEYS before it is cached or printed, and a hit becomes an
error. Times are relative minutes so they cannot narrow a timezone.

The field once read its span from the radar manifest, so on a cold cache it raced the radar run and showed nothing
until the next tick. The span is a pure function of the latitude, so both halves compute it with radar_span_km.
"""

import concurrent.futures
import datetime
import functools
import http.client
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

# -----------------------------------------------------------------------------
# CONSTANTS
# -----------------------------------------------------------------------------

TOGGLES_DIR = os.path.join(os.environ.get("QS_DOTFILES_DIR") or os.path.expanduser("~/projects/arch-dotfiles"), "toggles")
CACHE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "quickshell")

# union of everything a provider could hand back that names or narrows the place
LEAK_KEYS = {
    "latitude", "longitude", "lat", "lon", "coords", "elevation", "timezone", "timezone_abbreviation", "sunrise",
    "sunset", "daylight_duration", "nearest_area", "location", "place", "area", "areadesc", "geocode", "polygon",
    "sendername", "sender", "web", "contact", "country", "county", "state", "city", "headline", "description",
    "instruction",
}

FORECAST_CACHE = os.path.join(CACHE_DIR, "weather.json")
FORECAST_TIMEOUT_S = 12
FORECAST_URL = (
    "https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}"
    "&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,is_day,precipitation,cloud_cover,"
    "wind_speed_10m,wind_direction_10m,wind_gusts_10m,uv_index,surface_pressure"
    "&hourly=temperature_2m,relative_humidity_2m,precipitation,precipitation_probability,weather_code"
    "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,"
    "wind_speed_10m_max,uv_index_max"
    "&timezone=auto&forecast_days=4&forecast_hours=24"
)
# reply key and open-meteo variable in reply order, a missing value reads as 0
FORECAST_CURRENT = (
    ("temp", "temperature_2m"), ("feelsLike", "apparent_temperature"), ("humidity", "relative_humidity_2m"),
    ("code", "weather_code"), ("isDay", "is_day"), ("precip", "precipitation"), ("cloud", "cloud_cover"),
    ("wind", "wind_speed_10m"), ("windDir", "wind_direction_10m"), ("gust", "wind_gusts_10m"), ("uv", "uv_index"),
    ("pressure", "surface_pressure"),
)
FORECAST_HOURLY = (
    ("temp", "temperature_2m"), ("humidity", "relative_humidity_2m"), ("precip", "precipitation"),
    ("pop", "precipitation_probability"), ("code", "weather_code"),
)
FORECAST_DAILY = (
    ("code", "weather_code"), ("hi", "temperature_2m_max"), ("lo", "temperature_2m_min"), ("precip", "precipitation_sum"),
    ("pop", "precipitation_probability_max"), ("windMax", "wind_speed_10m_max"), ("uvMax", "uv_index_max"),
)
# windy is not a wmo code, beaufort 6
WINDY_KMH = 39.0

RADAR_DIR = os.path.join(CACHE_DIR, "radar")
RADAR_MANIFEST = os.path.join(RADAR_DIR, "manifest.json")
# z=7 is roughly a 400 km square
RADAR_ZOOM = 7
RADAR_SIZE_PX = 512
# universal blue palette, smoothed, snow separate
RADAR_COLOUR = "4"
RADAR_OPTIONS = "1_1"
RADAR_HISTORY_MIN = 240
RADAR_STEP_MIN = 10
# upstream index advances every ten minutes
RADAR_MAX_AGE_S = 540
RADAR_DOWNLOADS_PARALLEL = 6
RADAR_INDEX_TIMEOUT_S = 12
RADAR_FRAME_TIMEOUT_S = 15
# newest dwd composite lands a few minutes late
DWD_LATENCY_S = 5 * 60
DWD_LAT_RANGE = (47.0, 55.1)
DWD_LON_RANGE = (5.8, 15.1)
DWD_URL = "https://maps.dwd.de/geoserver/dwd/wms?"
RAINVIEWER_INDEX_URL = "https://api.rainviewer.com/public/weather-maps.json"
RAINVIEWER_HOST = "https://tilecache.rainviewer.com"
# web mercator metres per pixel at the equator, zoom 0
MERCATOR_Z0_M_PER_PX = 156543.03392
EARTH_RADIUS_M = 6378137.0

FIELD_CACHE = os.path.join(CACHE_DIR, "weather-field.json")
FIELD_GRID = 5
FIELD_MAX_AGE_S = 540
FIELD_TIMEOUT_S = 20
METRES_PER_DEGREE_LAT = 111320.0

ALERTS_CACHE = os.path.join(CACHE_DIR, "weather-alerts.json")
PLACE_CACHE = os.path.join(CACHE_DIR, "weather-place.json")
FEED_CACHE = os.path.join(CACHE_DIR, "weather-alerts-feed.json")
PLACE_MAX_AGE_S = 30 * 24 * 3600
# widget refreshes on every hover, feeds rate-limit
FEED_MAX_AGE_S = 600
PLACE_TIMEOUT_S = 15
FEED_TIMEOUT_S = 20
# zoom=8 is county level, never street level
NOMINATIM_URL = (
    "https://nominatim.openstreetmap.org/reverse?format=jsonv2&addressdetails=1&zoom=8&accept-language=en"
    "&lat={lat}&lon={lon}"
)
# nominatim refuses requests without a user agent
NOMINATIM_USER_AGENT = "arch-dotfiles-quickshell/1.0 (personal desktop shell)"
FEED_URL = "https://feeds.meteoalarm.org/api/v1/warnings/feeds-{slug}"
FEED_SLUGS = {
    "at": "austria", "ba": "bosnia-herzegovina", "be": "belgium", "bg": "bulgaria", "ch": "switzerland",
    "cy": "cyprus", "cz": "czechia", "de": "germany", "dk": "denmark", "ee": "estonia", "es": "spain",
    "fi": "finland", "fr": "france", "gb": "united-kingdom", "gr": "greece", "hr": "croatia", "hu": "hungary",
    "ie": "ireland", "il": "israel", "is": "iceland", "it": "italy", "lt": "lithuania", "lu": "luxembourg",
    "lv": "latvia", "md": "moldova", "me": "montenegro", "mk": "north-macedonia", "mt": "malta",
    "nl": "netherlands", "no": "norway", "pl": "poland", "pt": "portugal", "ro": "romania", "rs": "serbia",
    "se": "sweden", "si": "slovenia", "sk": "slovakia", "ua": "ukraine",
}
# generic admin words stripped so area names match by token
AREA_WORDS_GENERIC = {
    "kreis", "landkreis", "stadt", "stadtkreis", "county", "city", "region", "province", "provincia", "departement",
    "département", "district", "council", "borough", "comune", "gemeente", "kommune", "and", "of", "the", "und", "de",
    "la", "le", "les", "der", "die", "das", "en", "y",
}
ADDRESS_KEYS = ("county", "state", "state_district", "region", "city", "municipality", "town", "province")
# yellow and up
ALERT_LEVEL_MIN = 2
ALERTS_COUNT_MAX = 6

# -----------------------------------------------------------------------------
# INTERNAL
# -----------------------------------------------------------------------------


def failure(error):
    return {"ok": False, "error": error}


def http_get(url, timeout_s, headers=None):
    """Body of a GET, error statuses included like curl -s; None when nothing came back."""
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers or {}), timeout=timeout_s) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        return error.read()
    except (OSError, ValueError, http.client.HTTPException):
        return None


def cache_is_fresh(path, max_age_s):
    try:
        stat = os.stat(path)
    except OSError:
        return False
    age_s = int(time.time()) - int(stat.st_mtime)
    return stat.st_size > 0 and 0 <= age_s < max_age_s


def json_load(path):
    try:
        with open(path) as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def cache_load(path, max_age_s):
    return json_load(path) if cache_is_fresh(path, max_age_s) else None


# atomic rename so concurrent readers never see a partial file
def file_save(path, body):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path + ".tmp", "wb") as handle:
            handle.write(body)
        os.replace(path + ".tmp", path)
    except OSError:
        pass


@functools.cache
def location_resolve():
    """(source, lat_text, lon_text) from the location toggle, None without an answer; texts go into urls verbatim."""
    try:
        line = subprocess.run([os.path.join(TOGGLES_DIR, "toggle-weather-location.sh"), "resolve"],
                              capture_output=True, text=True, check=False).stdout.split()
    except OSError:
        return None
    if len(line) < 2 or line[0] == "none":
        return None
    coords = line[1].split(",")
    try:
        float(coords[0]), float(coords[-1])
    except ValueError:
        return None
    return line[0], coords[0], coords[-1]


def location_leak_find(node, path=""):
    """Path of the first LEAK_KEYS key anywhere in node, None when clean."""
    if isinstance(node, dict):
        for key, value in node.items():
            if key.lower() in LEAK_KEYS:
                return path + "." + key
            found = location_leak_find(value, path + "." + key)
            if found:
                return found
    elif isinstance(node, list):
        for index, value in enumerate(node):
            found = location_leak_find(value, f"{path}[{index}]")
            if found:
                return found
    return None


def reply_publish(reply, cache_path):
    """The reply, cached at cache_path, or an error when it would leak the location."""
    leak = location_leak_find(reply)
    if leak:
        return failure("location field leaked: " + leak)
    file_save(cache_path, json.dumps(reply).encode())
    return reply


def series_get(source, key, index=None, default=None):
    value = source.get(key)
    if value is not None and index is not None:
        value = value[index] if isinstance(value, list) and index < len(value) else None
    return default if value is None else value


# -----------------------------------------------------------------------------
# FORECAST
# -----------------------------------------------------------------------------


def forecast_get():
    location = location_resolve()
    if not location:
        return failure("no location")
    source, lat, lon = location
    raw = http_get(FORECAST_URL.format(lat=lat, lon=lon), FORECAST_TIMEOUT_S)
    if not raw:
        stale = json_load(FORECAST_CACHE)
        if not stale:
            return failure("offline")
        stale["stale"] = True
        return stale
    try:
        d = json.loads(raw)
    except ValueError:
        return failure("bad response")
    if "current" not in d or "daily" not in d:
        return failure(str(d.get("reason", "unexpected response"))[:120])

    c, hr, dy = d["current"], d.get("hourly", {}), d["daily"]
    hours = []
    for i, stamp in enumerate(hr.get("time", []) or []):
        try:
            # hour only, never the full timestamp
            hour = datetime.datetime.fromisoformat(stamp).strftime("%H")
        except (TypeError, ValueError):
            continue
        hours.append({"h": hour} | {key: series_get(hr, var, i, 0) for key, var in FORECAST_HOURLY})

    days = []
    today = datetime.datetime.now(datetime.UTC).astimezone().date()
    for i, stamp in enumerate(dy.get("time", []) or []):
        try:
            date = datetime.date.fromisoformat(stamp)
            delta = (date - today).days
            label = "Today" if delta == 0 else ("Tomorrow" if delta == 1 else date.strftime("%a"))
        except (TypeError, ValueError):
            label = "?"
        day = {"label": label} | {key: series_get(dy, var, i, 0) for key, var in FORECAST_DAILY}
        day["windy"] = bool(day["windMax"] and day["windMax"] >= WINDY_KMH)
        days.append(day)

    current = {key: series_get(c, var, None, 0) for key, var in FORECAST_CURRENT}
    # day unless the provider says night
    current["isDay"] = series_get(c, "is_day", None, 1)
    units = d.get("current_units", {}) or {}
    return reply_publish({
        "ok": True,
        # how the location was found, not where
        "source": source,
        "stale": False,
        "current": current,
        "units": {
            "temp":   units.get("temperature_2m", "°C"),
            "wind":   units.get("wind_speed_10m", "km/h"),
            "precip": units.get("precipitation", "mm"),
        },
        "hourly": hours,
        "daily": days,
    }, FORECAST_CACHE)


# -----------------------------------------------------------------------------
# RADAR
# -----------------------------------------------------------------------------


# web mercator ground resolution times image edge
def radar_span_km(lat):
    metres_per_px = MERCATOR_Z0_M_PER_PX * math.cos(math.radians(lat)) / (2 ** RADAR_ZOOM)
    return round(RADAR_SIZE_PX * metres_per_px / 1000.0)


def radar_plan_dwd(lat, lon):
    """(unix_s, url, is_forecast) per frame from the dwd wms."""
    x = math.radians(lon) * EARTH_RADIUS_M
    y = math.log(math.tan(math.pi / 4 + math.radians(lat) / 2)) * EARTH_RADIUS_M
    half = RADAR_SIZE_PX * MERCATOR_Z0_M_PER_PX / 2 ** RADAR_ZOOM / 2
    step_s = RADAR_STEP_MIN * 60
    latest = (int(time.time()) - DWD_LATENCY_S) // step_s * step_s
    plan = []
    for unix_s in range(latest - RADAR_HISTORY_MIN * 60, latest + 1, step_s):
        query = urllib.parse.urlencode({
            "service": "WMS", "version": "1.1.1", "request": "GetMap",
            "layers": "dwd:Radar_rv_product_1x1km_ger", "styles": "",
            "srs": "EPSG:3857", "bbox": f"{x - half:f},{y - half:f},{x + half:f},{y + half:f}",
            "width": RADAR_SIZE_PX, "height": RADAR_SIZE_PX, "format": "image/png", "transparent": "true",
            "time": time.strftime("%Y-%m-%dT%H:%M:00.000Z", time.gmtime(unix_s)),
        })
        plan.append((unix_s, DWD_URL + query, False))
    return plan


def radar_plan_rainviewer(lat, lon):
    """(plan, None) from the rainviewer index, or (None, error)."""
    body = http_get(RAINVIEWER_INDEX_URL, RADAR_INDEX_TIMEOUT_S)
    if not body:
        return None, "offline"
    try:
        index = json.loads(body)
        radar = index.get("radar") or {}
        frames = [(f, False) for f in (radar.get("past") or [])] + [(f, True) for f in (radar.get("nowcast") or [])]
        host = index.get("host", RAINVIEWER_HOST)
        tile = f"/{RADAR_SIZE_PX}/{RADAR_ZOOM}/{lat}/{lon}/{RADAR_COLOUR}/{RADAR_OPTIONS}.png"
        plan = [(int(f.get("time", 0)), host + f.get("path", "") + tile, forecast)
                for f, forecast in frames[-(RADAR_HISTORY_MIN // RADAR_STEP_MIN + 1):]]
    except (ValueError, TypeError, AttributeError):
        return None, "bad index"
    return (plan, None) if plan else (None, "bad index")


# drops truncated bodies and error pages
def radar_frame_download(path, url):
    body = http_get(url, RADAR_FRAME_TIMEOUT_S)
    if body and b"PNG" in body[:8]:
        file_save(path, body)


def radar_get():
    """Manifest of local frame paths; each refresh stages its own frame dir and the manifest is the switch."""
    cached = cache_load(RADAR_MANIFEST, RADAR_MAX_AGE_S)
    if cached:
        return cached
    location = location_resolve()
    if not location:
        return failure("no location")
    lat, lon = float(location[1]), float(location[2])

    # dwd inside germany, rainviewer elsewhere
    if DWD_LAT_RANGE[0] <= lat <= DWD_LAT_RANGE[1] and DWD_LON_RANGE[0] <= lon <= DWD_LON_RANGE[1]:
        plan, attribution = radar_plan_dwd(lat, lon), "Deutscher Wetterdienst"
    else:
        plan, error = radar_plan_rainviewer(lat, lon)
        if not plan:
            return failure(error)
        attribution = "RainViewer"

    now = int(time.time())
    stage = os.path.join(RADAR_DIR, f"f-{now}")
    shutil.rmtree(stage, ignore_errors=True)
    try:
        os.makedirs(stage)
    except OSError:
        return failure("cache unavailable")
    paths = [os.path.join(stage, f"frame-{i:02d}.png") for i in range(len(plan))]
    with concurrent.futures.ThreadPoolExecutor(RADAR_DOWNLOADS_PARALLEL) as pool:
        list(pool.map(radar_frame_download, paths, [url for _, url, _ in plan]))

    frames = [{
        "file": path,
        "minutes": round((unix_s - now) / 60.0),
        "forecast": forecast,
    } for path, (unix_s, _, forecast) in zip(paths, plan) if os.path.exists(path)]
    reply = failure("no frames")
    if frames:
        # licence condition, the attribution must be displayed
        reply = reply_publish({"ok": True, "frames": frames, "spanKm": radar_span_km(lat), "attribution": attribution},
                              RADAR_MANIFEST)
    # prune only after publishing, a failed run keeps the live generation
    stale = [n for n in os.listdir(RADAR_DIR) if n.startswith("f-") and n != os.path.basename(stage)]
    for name in stale if reply["ok"] else [os.path.basename(stage)]:
        shutil.rmtree(os.path.join(RADAR_DIR, name), ignore_errors=True)
    return reply


def field_get():
    """Wind and msl pressure on a FIELD_GRID square over the radar square, (u, v) from the top left in 0..1."""
    cached = cache_load(FIELD_CACHE, FIELD_MAX_AGE_S)
    if cached:
        return cached
    location = location_resolve()
    if not location:
        return failure("no location")
    lat0, lon0 = float(location[1]), float(location[2])

    half_m = radar_span_km(lat0) * 1000.0 / 2.0
    # longitude degrees shrink with latitude
    dlat = half_m / METRES_PER_DEGREE_LAT
    dlon = half_m / (METRES_PER_DEGREE_LAT * max(0.15, math.cos(math.radians(lat0))))
    points = []
    for row in range(FIELD_GRID):
        for col in range(FIELD_GRID):
            u, v = col / (FIELD_GRID - 1.0), row / (FIELD_GRID - 1.0)
            points.append((u, v, lat0 + dlat * (1.0 - 2.0 * v), lon0 + dlon * (2.0 * u - 1.0)))

    query = urllib.parse.urlencode({
        "latitude": ",".join(f"{p[2]:.4f}" for p in points),
        "longitude": ",".join(f"{p[3]:.4f}" for p in points),
        # msl, surface pressure would contour the terrain
        "current": "wind_speed_10m,wind_direction_10m,pressure_msl",
        "timezone": "auto",
    })
    body = http_get("https://api.open-meteo.com/v1/forecast?" + query, FIELD_TIMEOUT_S)
    try:
        payload = json.loads(body)
    except (TypeError, ValueError):
        return failure("offline")
    # one coordinate yields an object, not a list
    if isinstance(payload, dict):
        payload = [payload]
    if not isinstance(payload, list) or len(payload) != len(points):
        return failure("unexpected response")

    cells, pressures = [], []
    for (u, v, _, _), entry in zip(points, payload):
        current = (entry or {}).get("current") or {}
        speed, direction, pressure = (current.get(k) for k in ("wind_speed_10m", "wind_direction_10m", "pressure_msl"))
        if speed is None or direction is None:
            continue
        # dir is where the wind comes from
        cell = {"u": round(u, 4), "v": round(v, 4), "wind": round(float(speed), 1),
                "dir": round(float(direction)) % 360}
        if pressure is not None:
            cell["hpa"] = round(float(pressure), 1)
            pressures.append(cell["hpa"])
        cells.append(cell)
    if not cells:
        return failure("no data")

    units = (payload[0] or {}).get("current_units") or {}
    out = {
        "ok": True,
        "grid": FIELD_GRID,
        "cells": cells,
        "windUnits": units.get("wind_speed_10m", "km/h"),
        "pressureUnits": units.get("pressure_msl", "hPa"),
    }
    if pressures:
        out["pressureMin"] = round(min(pressures), 1)
        out["pressureMax"] = round(max(pressures), 1)
    return reply_publish(out, FIELD_CACHE)


# -----------------------------------------------------------------------------
# ALERTS
# -----------------------------------------------------------------------------


def area_tokens(text):
    text = unicodedata.normalize("NFKD", str(text or ""))
    text = re.sub(r"[^a-z0-9 ]+", " ", "".join(c for c in text if not unicodedata.combining(c)).lower())
    return {t for t in text.split() if len(t) > 3 and t not in AREA_WORDS_GENERIC}


# cap polygons are "lat,lon lat,lon ...", closed ring
def polygon_contains(polygon, lat, lon):
    points = []
    for pair in str(polygon or "").split():
        try:
            a, b = pair.split(",")
            points.append((float(a), float(b)))
        except ValueError:
            return False
    if len(points) < 4:
        return False
    inside = False
    for i, (y1, x1) in enumerate(points):
        y2, x2 = points[(i + 1) % len(points)]
        if (y1 > lat) != (y2 > lat) and y2 != y1 and lon < x1 + (lat - y1) * (x2 - x1) / (y2 - y1):
            inside = not inside
    return inside


# parameter values look like "2; yellow; Moderate"
def alert_awareness(info):
    level, colour, kind = 0, "", ""
    for parameter in info.get("parameter") or []:
        name = str(parameter.get("valueName", "")).lower()
        value = str(parameter.get("value", ""))
        bits = [b.strip() for b in value.split(";")]
        if name == "awareness_level":
            if bits and bits[0].isdigit():
                level = int(bits[0])
            if len(bits) > 1:
                colour = bits[1].lower()
        elif name == "awareness_type":
            kind = bits[1] if len(bits) > 1 else value
    return level, colour, kind


# english when the feed has it
def alert_info_pick(alert):
    infos = alert.get("info") or []
    for info in infos:
        languages = info.get("language")
        languages = languages if isinstance(languages, list) else [languages]
        if any(str(language or "").lower().startswith("en") for language in languages):
            return info
    return infos[0] if infos else None


# relative so it cannot hint the timezone
def iso_to_minutes(value):
    try:
        moment = datetime.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=datetime.timezone.utc)
    return round((moment - datetime.datetime.now(datetime.UTC)).total_seconds() / 60.0)


def alerts_get():
    cached = cache_load(ALERTS_CACHE, FEED_MAX_AGE_S)
    if cached:
        return cached
    location = location_resolve()
    if not location:
        return failure("no location")
    _, lat_text, lon_text = location
    lat, lon = float(lat_text), float(lon_text)

    if not cache_is_fresh(PLACE_CACHE, PLACE_MAX_AGE_S):
        body = http_get(NOMINATIM_URL.format(lat=lat_text, lon=lon_text), PLACE_TIMEOUT_S,
                        {"User-Agent": NOMINATIM_USER_AGENT})
        if body:
            file_save(PLACE_CACHE, body)
    place = json_load(PLACE_CACHE)
    address = (place.get("address") or {}) if isinstance(place, dict) else {}
    if not address.get("country_code"):
        return failure("no region")
    slug = FEED_SLUGS.get(address["country_code"])
    if not slug:
        return {"ok": True, "supported": False, "alerts": [], "countryOthers": 0}

    if not cache_is_fresh(FEED_CACHE, FEED_MAX_AGE_S):
        body = http_get(FEED_URL.format(slug=slug), FEED_TIMEOUT_S)
        if body:
            file_save(FEED_CACHE, body)
    feed = json_load(FEED_CACHE)
    if not isinstance(feed, dict):
        return failure("offline")

    mine = set()
    for key in ADDRESS_KEYS:
        mine |= area_tokens(address.get(key))
    alerts, others, seen = [], 0, set()
    for warning in feed.get("warnings") or []:
        info = alert_info_pick(warning.get("alert") or {})
        if not info:
            continue
        # here is a polygon hit, region only a name match
        scope = ""
        for area in info.get("area") or []:
            polygons = area.get("polygon")
            polygons = polygons if isinstance(polygons, list) else ([polygons] if polygons else [])
            if any(polygon_contains(p, lat, lon) for p in polygons):
                scope = "here"
                break
            if mine and area_tokens(area.get("areaDesc")) & mine:
                scope = "region"
        ends_in = iso_to_minutes(info.get("expires"))
        if ends_in is not None and ends_in < 0:
            continue
        level, colour, kind = alert_awareness(info)
        # filtered before others is counted
        if level < ALERT_LEVEL_MIN:
            continue
        if not scope:
            others += 1
            continue
        key = (str(info.get("event", "")), level, scope)
        if key in seen:
            continue
        seen.add(key)
        # no free text, event is a short controlled phrase
        alerts.append({
            "event":     str(info.get("event", "") or kind or "Weather warning")[:80],
            "severity":  str(info.get("severity", "")),
            "urgency":   str(info.get("urgency", "")),
            "certainty": str(info.get("certainty", "")),
            "level":     level,
            "colour":    colour,
            "kind":      kind,
            "scope":     scope,
            "startsIn":  iso_to_minutes(info.get("onset") or info.get("effective")),
            "endsIn":    ends_in,
        })
    alerts.sort(key=lambda a: (-a["level"], a["scope"] != "here"))
    return reply_publish({"ok": True, "supported": True, "alerts": alerts[:ALERTS_COUNT_MAX], "countryOthers": others},
                         ALERTS_CACHE)


# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "forecast":
        reply = forecast_get()
    elif command == "radar":
        reply = {"radar": radar_get(), "field": field_get()}
    elif command == "alerts":
        reply = alerts_get()
        reply.setdefault("alerts", [])
    else:
        print("usage: weather.py forecast|radar|alerts", file=sys.stderr)
        return 2
    print(json.dumps(reply))
    return 0


if __name__ == "__main__":
    sys.exit(main())
