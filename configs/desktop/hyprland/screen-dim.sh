#!/usr/bin/env bash
# idle dim and restore: laptop backlight via brightnessctl, external ddc/ci monitors via ddcutil
# the pre-dim level per device is saved so resume brings it back
set -u

state="${XDG_RUNTIME_DIR:-/run/user/$UID}/screen-dim"
DDC_LOW=10
DDC_BUS_MAP="$HOME/.cache/ddcutil-bus-map.tsv"

has_backlight() { compgen -G '/sys/class/backlight/*' >/dev/null; }

case "${1:-}" in
dim)
    # already dimmed: do not overwrite the saved baseline with the dimmed level
    [[ -f "$state" ]] && exit 0
    if has_backlight; then
        brightnessctl -s set 10
        : >"$state"
        exit 0
    fi
    : >"$state"
    # the bus map from monitor-brightness.sh skips a slow detect; ddc is slow, so one job per monitor
    buses=$(cut -f2 "$DDC_BUS_MAP" 2>/dev/null)
    [[ -n "$buses" ]] || buses=$(ddcutil detect --terse 2>/dev/null | sed -n 's|.*/dev/i2c-\([0-9]*\).*|\1|p')
    for bus in $buses; do
        {
            cur=$(ddcutil --bus "$bus" getvcp 10 --terse 2>/dev/null | awk '{print $4}')
            [[ "$cur" =~ ^[0-9]+$ ]] && echo "$bus $cur" >>"$state" \
                && ddcutil --bus "$bus" setvcp 10 "$DDC_LOW" --noverify 2>/dev/null
        } &
    done
    wait
    ;;
restore)
    [[ -f "$state" ]] || exit 0
    if has_backlight; then
        brightnessctl -r
        rm -f "$state"
        exit 0
    fi
    while read -r bus cur; do
        [[ "$cur" =~ ^[0-9]+$ ]] && ddcutil --bus "$bus" setvcp 10 "$cur" --noverify 2>/dev/null &
    done <"$state"
    wait
    rm -f "$state"
    ;;
*)
    echo "usage: $(basename "$0") {dim|restore}" >&2
    exit 1
    ;;
esac
