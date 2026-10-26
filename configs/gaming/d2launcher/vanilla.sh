#!/bin/bash
# plain lord of destruction 1.14d, windowed: its direct3d fullscreen mode fails under wine at most sizes
cd "@game@" || exit 1
export WINEPREFIX="@prefix@" PIPEWIRE_ALSA='{ application.name="Diablo II: Lord of Destruction" }'
# the fastest output's rate at launch, not at apply time (an apply from a tty sees no hyprland)
refresh=$(hyprctl -j monitors 2> /dev/null | jq -r '[.[] | select(.name | test("^HEADLESS-") | not) | .refreshRate] | max // 60 | round')
# shellcheck disable=SC2016
exec gamescope -w 800 -h 600 -r "${refresh:-60}" -S fit -F linear -- \
    sh -c '"$1/wine" start /wait /unix Game.exe -w; "$1/wineserver" -w' sh "@wine@"
