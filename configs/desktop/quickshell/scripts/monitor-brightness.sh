#!/usr/bin/env bash
# per-monitor brightness keyed by hyprland output name
set -uo pipefail

CACHE="$HOME/.cache/ddcutil-bus-map.tsv"
SLEEP_MULT=0.2

refresh_cache() {
    mkdir -p "$(dirname "$CACHE")"
    ddcutil detect --brief 2>/dev/null | awk '
        /I2C bus:/      { bus = $NF; sub(/.*i2c-/, "", bus) }
        /DRM connector:/ { conn = $NF; sub(/^card[0-9]+-/, "", conn); print conn "\t" bus }
    ' > "$CACHE.new" && mv -f "$CACHE.new" "$CACHE"
}

# empty if the output is not ddc-capable
bus_for() {
    local connector="$1"
    [[ -s "$CACHE" ]] || refresh_cache
    local bus
    bus=$(awk -F'\t' -v c="$connector" '$1 == c { print $2; exit }' "$CACHE" 2>/dev/null)
    if [[ -z "$bus" ]]; then
        # may be a monitor plugged in after the cache was built
        refresh_cache
        bus=$(awk -F'\t' -v c="$connector" '$1 == c { print $2; exit }' "$CACHE" 2>/dev/null)
    fi
    echo "$bus"
}

has_backlight() { [[ -n "$(ls /sys/class/backlight/ 2>/dev/null)" ]]; }

get_pct() {
    local connector="$1"
    if [[ "$connector" == eDP* ]] && has_backlight; then
        local cur max
        cur=$(brightnessctl -m get 2>/dev/null) || return 1
        max=$(brightnessctl -m max 2>/dev/null) || return 1
        ((max > 0)) && echo $(( cur * 100 / max )) || echo 0
        return 0
    fi
    local bus
    bus=$(bus_for "$connector")
    [[ -n "$bus" ]] || return 1
    ddcutil --bus "$bus" --sleep-multiplier "$SLEEP_MULT" getvcp 10 --brief 2>/dev/null \
        | awk '{ print $4 }'
}

set_pct() {
    local connector="$1" pct="$2"
    ((pct < 0)) && pct=0
    ((pct > 100)) && pct=100
    if [[ "$connector" == eDP* ]] && has_backlight; then
        brightnessctl -q set "${pct}%" >/dev/null 2>&1
        return $?
    fi
    local bus
    bus=$(bus_for "$connector")
    [[ -n "$bus" ]] || return 1
    ddcutil --bus "$bus" --noverify --sleep-multiplier "$SLEEP_MULT" setvcp 10 "$pct" >/dev/null 2>&1
}

case "${1:-}" in
get)      get_pct "$2" ;;
set)      set_pct "$2" "$3" ;;
--refresh|refresh) refresh_cache ;;
*)
    echo "usage: $(basename "$0") {get <connector>|set <connector> <pct>|refresh}" >&2
    exit 1
    ;;
esac
