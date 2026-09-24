#!/usr/bin/env bash
# Severe-weather warnings for the current location, from MeteoAlarm's CAP feeds, sanitised the same way weather-fetch.sh sanitises the forecast.
set -uo pipefail

TOGGLES="${QS_DOTFILES_DIR:-$HOME/projects/arch-dotfiles}/toggles"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell"
PLACE_CACHE="$CACHE/weather-place.json"
FEED_CACHE="$CACHE/weather-alerts-feed.json"
OUT_CACHE="$CACHE/weather-alerts.json"

# Administrative boundaries do not move.
PLACE_MAX_AGE=$(( 30 * 24 * 3600 ))
# Warnings are issued on the scale of hours; national services rate-limit harder than that and the widget refreshes on every hover.
FEED_MAX_AGE=600

fail() { printf '{"ok":false,"error":"%s","alerts":[]}\n' "$1"; exit 0; }

# The cache directory is NOT guaranteed to exist.
mkdir -p "$CACHE" 2>/dev/null || fail "cache unavailable"

fresh() { # path, max-age
    [[ -s "$1" ]] || return 1
    local age=$(( $(date +%s) - $(stat -c %Y "$1" 2>/dev/null || echo 0) ))
    (( age >= 0 && age < $2 ))
}

if fresh "$OUT_CACHE" "$FEED_MAX_AGE"; then
    cat "$OUT_CACHE"
    exit 0
fi

read -r SOURCE COORDS <<<"$("$TOGGLES/toggle-weather-location.sh" resolve 2>/dev/null || echo none)"
[[ "$SOURCE" == "none" || -z "${COORDS:-}" ]] && fail "no location"
LAT=${COORDS%%,*}
LON=${COORDS##*,}

# ---- 1. which country, and which administrative areas ---------------------- zoom=8 asks Nominatim for county-level detail: enough to match a CAP region, not so fine that the reply names a street. The coordinate sent is the same 2-decimal-place value the forecast already uses.
if ! fresh "$PLACE_CACHE" "$PLACE_MAX_AGE"; then
    # A User-Agent is mandatory under Nominatim's usage policy; an anonymous request is refused.
    curl -s --max-time 15 \
        -A "arch-dotfiles-quickshell/1.0 (personal desktop shell)" \
        "https://nominatim.openstreetmap.org/reverse?format=jsonv2&addressdetails=1&zoom=8&accept-language=en&lat=${LAT}&lon=${LON}" \
        -o "$PLACE_CACHE.tmp" 2>/dev/null \
        && [[ -s "$PLACE_CACHE.tmp" ]] \
        && mv "$PLACE_CACHE.tmp" "$PLACE_CACHE"
    rm -f "$PLACE_CACHE.tmp"
fi
[[ -s "$PLACE_CACHE" ]] || fail "no region"

# Path passed as argv, not interpolated into the program text: every other python call in this file and its siblings does it that way, and a $HOME containing a quote turns interpolation into a syntax error at best.
COUNTRY_CODE=$(python3 - "$PLACE_CACHE" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print((d.get('address') or {}).get('country_code', ''))
except Exception:
    print('')
PY
)
[[ -z "$COUNTRY_CODE" ]] && fail "no region"

# MeteoAlarm's feed slugs.
declare -A SLUGS=(
    [at]=austria [ba]=bosnia-herzegovina [be]=belgium [bg]=bulgaria
    [ch]=switzerland [cy]=cyprus [cz]=czechia [de]=germany [dk]=denmark
    [ee]=estonia [es]=spain [fi]=finland [fr]=france [gb]=united-kingdom
    [gr]=greece [hr]=croatia [hu]=hungary [ie]=ireland [il]=israel
    [is]=iceland [it]=italy [lt]=lithuania [lu]=luxembourg [lv]=latvia
    [md]=moldova [me]=montenegro [mk]=north-macedonia [mt]=malta
    [nl]=netherlands [no]=norway [pl]=poland [pt]=portugal [ro]=romania
    [rs]=serbia [se]=sweden [si]=slovenia [sk]=slovakia [ua]=ukraine
)
SLUG=${SLUGS[$COUNTRY_CODE]:-}
[[ -z "$SLUG" ]] && { printf '{"ok":true,"supported":false,"alerts":[],"countryOthers":0}\n'; exit 0; }

# ---- 2. the country's live warnings ----------------------------------------
if ! fresh "$FEED_CACHE" "$FEED_MAX_AGE"; then
    curl -s --max-time 20 "https://feeds.meteoalarm.org/api/v1/warnings/feeds-${SLUG}" \
        -o "$FEED_CACHE.tmp" 2>/dev/null \
        && [[ -s "$FEED_CACHE.tmp" ]] \
        && mv "$FEED_CACHE.tmp" "$FEED_CACHE"
    rm -f "$FEED_CACHE.tmp"
fi
[[ -s "$FEED_CACHE" ]] && [[ "$(head -c 1 "$FEED_CACHE")" == "{" ]] || fail "offline"

# ---- 3. select, classify, strip --------------------------------------------
python3 - "$FEED_CACHE" "$PLACE_CACHE" "$LAT" "$LON" "$OUT_CACHE" <<'PY'
import json, sys, re, unicodedata, datetime

feed_path, place_path, lat, lon, out_path = (
    sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4]), sys.argv[5])

def jload(p):
    try:
        with open(p) as f: return json.load(f)
    except Exception:
        return {}

feed = jload(feed_path)
place = jload(place_path)

# ---- our own area names, normalised ----------------------------------------
#
# Generic administrative words are stripped before comparing. "Landkreis
# Eichsfeld" and "Kreis Eichsfeld" are the same place to a human and share no
# whole string; what identifies them is the token "eichsfeld".
GENERIC = {
    "kreis", "landkreis", "stadt", "stadtkreis", "county", "city", "region",
    "province", "provincia", "departement", "département", "district",
    "council", "borough", "comune", "gemeente", "kommune", "and", "of", "the",
    "und", "de", "la", "le", "les", "der", "die", "das", "en", "y",
}

def norm(s):
    s = unicodedata.normalize("NFKD", str(s or ""))
    s = "".join(c for c in s if not unicodedata.combining(c)).lower()
    return re.sub(r"[^a-z0-9 ]+", " ", s)

def tokens(s):
    return {t for t in norm(s).split() if len(t) > 3 and t not in GENERIC}

addr = place.get("address") or {}
mine = set()
for key in ("county", "state", "state_district", "region", "city",
            "municipality", "town", "province"):
    mine |= tokens(addr.get(key))

# ---- point in polygon ------------------------------------------------------
#
# CAP polygons are "lat,lon lat,lon ..." with the ring closed. Ray casting in
# plain degrees is accurate enough at warning-area scale; the alternative is
# projecting, for a decision that is already coarse.
def in_polygon(poly_str, plat, plon):
    pts = []
    for pair in str(poly_str or "").split():
        try:
            a, b = pair.split(",")
            pts.append((float(a), float(b)))
        except Exception:
            return False
    if len(pts) < 4:
        return False
    inside = False
    n = len(pts)
    for i in range(n):
        y1, x1 = pts[i]
        y2, x2 = pts[(i + 1) % n]
        if (y1 > plat) != (y2 > plat):
            if y2 != y1 and plon < x1 + (plat - y1) * (x2 - x1) / (y2 - y1):
                inside = not inside
    return inside

# ---- awareness colour ------------------------------------------------------
#
# MeteoAlarm's own scale, carried in a CAP parameter as "2; yellow; Moderate".
# Preferred over CAP `severity` because it is what the national services
# actually calibrate and what users recognise.
def awareness(info):
    level, colour, kind = 0, "", ""
    for p in info.get("parameter") or []:
        name = str(p.get("valueName", "")).lower()
        val = str(p.get("value", ""))
        if name == "awareness_level":
            bits = [b.strip() for b in val.split(";")]
            if bits and bits[0].isdigit(): level = int(bits[0])
            if len(bits) > 1: colour = bits[1].lower()
        elif name == "awareness_type":
            bits = [b.strip() for b in val.split(";")]
            kind = bits[1] if len(bits) > 1 else val
    return level, colour, kind

def pick_info(alert):
    infos = alert.get("info") or []
    if not infos:
        return None
    for i in infos:
        langs = i.get("language")
        langs = langs if isinstance(langs, list) else [langs]
        if any(str(l or "").lower().startswith("en") for l in langs):
            return i
    return infos[0]

def iso_minutes(value):
    # Emitted as minutes-from-now, not as a timestamp: an absolute local time
    # in a screenshot is a timezone hint, which is a location hint.
    try:
        dt = datetime.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except Exception:
        return None
    now = datetime.datetime.now(datetime.timezone.utc)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.timezone.utc)
    return int(round((dt - now).total_seconds() / 60.0))

alerts = []
others = 0
seen = set()

for warning in feed.get("warnings") or []:
    alert = warning.get("alert") or {}
    info = pick_info(alert)
    if not info:
        continue

    scope = ""
    for area in info.get("area") or []:
        poly = area.get("polygon")
        polys = poly if isinstance(poly, list) else ([poly] if poly else [])
        if any(in_polygon(p, lat, lon) for p in polys):
            scope = "here"
            break
        if mine and tokens(area.get("areaDesc")) & mine:
            scope = "region"

    expires = iso_minutes(info.get("expires"))
    # Already over. Feeds keep expired warnings around briefly.
    if expires is not None and expires < 0:
        continue

    level, colour, kind = awareness(info)
    # Green/level-1 is MeteoAlarm's "no particular awareness required" tier and
    # the feeds are full of it — the Dutch feed alone carried 493 warnings, the
    # overwhelming majority green. Listing those turns a warnings panel into a
    # weather-is-happening panel. Yellow (2) and up only.
    #
    # FILTERED BEFORE `others` IS COUNTED, not after. The counter feeds the
    # panel's "N more warnings elsewhere in your country" line, so counting the
    # green tier here while refusing to list it meant that line reported a
    # number the panel would never show anything for — 487, on the Dutch feed
    # above. `others` now means "warnings I would have listed, but they are not
    # near you", which is the only reading that makes the sentence true.
    if level < 2:
        continue

    if not scope:
        others += 1
        continue

    key = (str(info.get("event", "")), level, scope)
    if key in seen:
        continue
    seen.add(key)

    # Free text is deliberately absent — see the header. `event` is a short
    # controlled phrase ("Wind", "Forest fire"), not prose.
    alerts.append({
        "event":     str(info.get("event", "") or kind or "Weather warning")[:80],
        "severity":  str(info.get("severity", "")),
        "urgency":   str(info.get("urgency", "")),
        "certainty": str(info.get("certainty", "")),
        "level":     level,
        "colour":    colour,
        "kind":      kind,
        "scope":     scope,
        "startsIn":  iso_minutes(info.get("onset") or info.get("effective")),
        "endsIn":    expires,
    })

# Worst first: a red warning under two yellows is a UI that buries the thing
# it exists to surface.
alerts.sort(key=lambda a: (-a["level"], a["scope"] != "here"))

out = {
    "ok": True,
    "supported": True,
    "alerts": alerts[:6],
    "countryOthers": others,
}

# Same assertion as weather-fetch.sh: a loud failure beats a quiet disclosure.
BANNED = {"areadesc", "area", "latitude", "longitude", "lat", "lon",
          "geocode", "polygon", "sendername", "sender", "web", "contact",
          "country", "county", "state", "city", "place",
          "headline", "description", "instruction"}
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
    print(json.dumps({"ok": False, "error": "location field leaked: " + leak,
                      "alerts": []}))
    sys.exit(0)

try:
    with open(out_path, "w") as f:
        json.dump(out, f)
except Exception:
    pass

print(json.dumps(out))
PY
