#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# Resolves the coordinates the weather widget queries with, and owns the manual-override state.

# NOT "$TOGGLES_STATE_DIR/weather-location": toggle_set writes its own on/off bookkeeping to exactly that path, so sharing the name meant toggle_main overwrote the stored coordinates with the literal string "on".
MANUAL_FILE="$TOGGLES_STATE_DIR/weather-location.coords"

round2() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.2f,%.2f", a, b }'; }

manual_coords() { [[ -s "$MANUAL_FILE" ]] && cat "$MANUAL_FILE" || true; }

# Needs an authorised agent to be running or it blocks and returns nothing, hence the hard timeout.
geoclue_coords() {
    local out lat lon
    local demo=/usr/lib/geoclue-2.0/demos/where-am-i
    [[ -x "$demo" ]] || return 0
    # Every one of these needs `|| true`.
    out=$(timeout 8 "$demo" -a 4 -t 6 2>/dev/null || true)
    [[ -n "$out" ]] || return 0
    lat=$(grep -oP 'Latitude:\s*\K-?[0-9.]+' <<<"$out" | head -1 || true)
    lon=$(grep -oP 'Longitude:\s*\K-?[0-9.]+' <<<"$out" | head -1 || true)
    [[ -n "$lat" && -n "$lon" ]] && round2 "$lat" "$lon" || true
}

# zone1970.tab ships a coordinate for every zone, so this is a plain file lookup: no network, no daemon, and identical whether or not a tunnel is up.
timezone_coords() {
    local tz tab coord
    tz=$(timedatectl show -p Timezone --value 2>/dev/null || true)
    [[ -n "$tz" ]] || return 0
    for tab in /usr/share/zoneinfo/zone1970.tab /usr/share/zoneinfo/zone.tab; do
        [[ -r "$tab" ]] || continue
        coord=$(awk -F'\t' -v tz="$tz" '
            /^#/ { next }
            {
                n = split($3, zones, ",")
                for (i = 1; i <= n; i++) if (zones[i] == tz) { print $2; exit }
            }' "$tab" || true)
        [[ -n "$coord" ]] || continue
        # ISO 6709: +DDMM[SS]+DDDMM[SS]
        python3 - "$coord" <<'PY' || true
import re, sys
m = re.match(r'([+-]\d{2})(\d{2})(\d{2})?([+-]\d{3})(\d{2})(\d{2})?$', sys.argv[1])
if m:
    la = int(m.group(1)) + int(m.group(2))/60 + int(m.group(3) or 0)/3600
    lo = int(m.group(4)) + int(m.group(5))/60 + int(m.group(6) or 0)/3600
    print(f"{la:.2f},{lo:.2f}")
PY
        return 0
    done
}

# Last resort, and the one the SPEC's "NOT REVEAL IT" pushes back on: it discloses the public IP to a third party, and behind Tor/ProtonVPN/ WireGuard it returns the exit node's city — silently showing the wrong country's weather while looking perfectly normal.
ipgeo_coords() {
    local j lat lon
    j=$(timeout 8 curl -s --max-time 6 'https://ipapi.co/json/' 2>/dev/null || true)
    [[ -n "$j" ]] || return 0
    lat=$(python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('latitude',''))" <<<"$j" 2>/dev/null || true)
    lon=$(python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('longitude',''))" <<<"$j" 2>/dev/null || true)
    [[ -n "$lat" && -n "$lon" ]] && round2 "$lat" "$lon" || true
}

resolve() {
    local c
    c=$(manual_coords   || true); [[ -n "$c" ]] && { echo "manual $c"; return; }
    c=$(geoclue_coords  || true); [[ -n "$c" ]] && { echo "geoclue $c"; return; }
    c=$(timezone_coords || true); [[ -n "$c" ]] && { echo "timezone $c"; return; }
    c=$(ipgeo_coords    || true); [[ -n "$c" ]] && { echo "ipgeo $c"; return; }
    echo "none"
}

check() { [[ -s "$MANUAL_FILE" ]] && echo on || echo off; }

# Pins whatever location is in use right now.
turn_on() {
    if [[ -s "$MANUAL_FILE" ]]; then return 0; fi
    local c
    read -r _ c <<<"$(resolve)"
    if [[ -z "${c:-}" ]]; then
        echo "no location could be resolved to pin; use: $(basename "$0") set <lat> <lon>" >&2
        return 0
    fi
    printf '%s' "$c" >"$MANUAL_FILE"
}
turn_off() { rm -f "$MANUAL_FILE"; }

case "${1:-toggle}" in
set)
    [[ $# -ge 2 ]] || { echo "usage: $(basename "$0") set <lat> <lon>" >&2; exit 1; }
    if [[ $# -ge 3 ]]; then lat=$2; lon=$3; else IFS=, read -r lat lon <<<"$2"; fi
    [[ -n "${lat:-}" && -n "${lon:-}" ]] || { echo "need both lat and lon" >&2; exit 1; }
    round2 "$lat" "$lon" >"$MANUAL_FILE"
    toggle_set weather-location on
    toggle_notify -a Toggles "Weather Location" "Set manually"
    cat "$MANUAL_FILE"; echo
    ;;
clear)
    turn_off
    toggle_set weather-location off
    toggle_notify -a Toggles "Weather Location" "Back to automatic"
    ;;
# "<source> <lat>,<lon>" — the widget reads both halves so the panel can say how the location was determined without ever rendering the location.
resolve) resolve ;;
coords)  read -r _ c <<<"$(resolve)"; echo "${c:-}" ;;
source)  read -r s _ <<<"$(resolve)"; echo "$s" ;;
*)
    toggle_main weather-location "Weather Location (manual)" check turn_on turn_off "${1:-toggle}"
    ;;
esac
