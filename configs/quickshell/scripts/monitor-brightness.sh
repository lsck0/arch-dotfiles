#!/usr/bin/env bash
# Per-monitor brightness control, keyed by Hyprland output name (DP-1, DP-2,
# eDP-1, HDMI-A-1, …) — what Display.qml already has for every monitor via
# `hyprctl monitors -j`.
#
# WHY THIS EXISTS. `brightnessctl` only drives Linux backlight class devices
# (/sys/class/backlight/*), which is the laptop panel and nothing else. On a
# desktop with external monitors there is no backlight device at all — the
# widget's old brightnessctl-only code path had nothing to control and the
# slider silently did nothing. External monitors are dimmed over DDC/CI
# (the same VESA protocol monitor OSD buttons use), which on Linux means
# ddcutil talking i2c to the monitor's EDID bus.
#
# WHY --bus, NOT --display/-d. `ddcutil -d N ...` (or bare `getvcp`/`setvcp`
# with no bus) re-probes every /dev/i2c-* device for a DDC-capable monitor
# on EVERY invocation — ~6s on this hardware, spec'd purely by ddcutil's own
# docs as "90% of elapsed time is spent in mandated protocol sleeps plus the
# probe". `--bus N` skips the probe entirely and goes straight to the known
# i2c device: ~0.4s. That is the actual bug behind the "buttons don't work"
# report — the widget likely wasn't hung, it was doing a 6s round trip on a
# UI thread / detached process with a short implicit timeout elsewhere, or
# simply felt broken because nothing visibly happened for 6 whole seconds.
#
# CACHING THE BUS MAP. `ddcutil detect` (which resolves connector -> bus) is
# the slow full-probe call ITSELF, so calling it per-brightness-change would
# defeat the point of --bus. The connector -> bus mapping is resolved once,
# cached to disk, and only re-probed when a requested connector is missing
# from the cache (new monitor / hotplug) or the caller passes --refresh.
set -uo pipefail

CACHE="$HOME/.cache/ddcutil-bus-map.tsv"
SLEEP_MULT=0.2

refresh_cache() {
    mkdir -p "$(dirname "$CACHE")"
    # `ddcutil detect --brief` blocks are separated by a blank line, each:
    #   Display N
    #      I2C bus:          /dev/i2c-9
    #      DRM connector:    card1-DP-1
    ddcutil detect --brief 2>/dev/null | awk '
        /I2C bus:/      { bus = $NF; sub(/.*i2c-/, "", bus) }
        /DRM connector:/ { conn = $NF; sub(/^card[0-9]+-/, "", conn); print conn "\t" bus }
    ' > "$CACHE.new" && mv -f "$CACHE.new" "$CACHE"
}

bus_for() { # connector -> i2c bus number, or empty if not DDC-capable
    local connector="$1"
    [[ -s "$CACHE" ]] || refresh_cache
    local bus
    bus=$(awk -F'\t' -v c="$connector" '$1 == c { print $2; exit }' "$CACHE" 2>/dev/null)
    if [[ -z "$bus" ]]; then
        # Not in the cache yet -- could be a genuinely non-DDC output
        # (eDP), or a monitor that appeared after the cache was built.
        # Reprobe once before giving up, but only once per call.
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
    # --noverify: skip ddcutil reading the value back to confirm the write
    # landed. Verification is another full DDC round trip (~doubles the
    # time); a dragged slider fires many of these in quick succession, so
    # skipping it is the difference between "instant" and "visibly laggy".
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
