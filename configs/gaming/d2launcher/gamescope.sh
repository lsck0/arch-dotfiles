#!/bin/bash
# a diablo ii build on d2launcher's wine in gamescope; median xl, plain lord of destruction and both pd2 seasons
cd "@game@" || exit 1
export WINEPREFIX="@prefix@" WINEDLLOVERRIDES="@dll_overrides@" PIPEWIRE_ALSA='{ application.name="@name@" }'
# the fastest output's rate at launch, not at apply time (an apply from a tty sees no hyprland)
refresh=$(command -v hyprctl > /dev/null && hyprctl -j monitors 2> /dev/null | jq -r '[.[] | select(.name | test("^HEADLESS-") | not) | .refreshRate] | max // 60 | round')
# shellcheck disable=SC2016
exec gamescope -w @width@ -h @height@ -r "${refresh:-60}" -S fit -F linear -- \
    sh -c '"$1/wine" start /wait /unix "$2" @args@; "$1/wineserver" -w' sh "@wine@" "@exe@"
