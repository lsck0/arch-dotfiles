#!/bin/bash
cd "@game@" || exit 1
export WINEPREFIX="@prefix@" PIPEWIRE_ALSA='{ application.name="Diablo II" }'
refresh=$(hyprctl -j monitors 2> /dev/null | jq -r '[.[] | select(.name | test("^HEADLESS-") | not) | .refreshRate] | max // 60 | round')
# shellcheck disable=SC2016
exec gamescope -w @width@ -h @height@ -r "${refresh:-60}" -S fit -F linear -- \
    sh -c '"$1/wine" start /wait /unix "$2" @args@; "$1/wineserver" -w' sh "@wine@" "@exe@"
