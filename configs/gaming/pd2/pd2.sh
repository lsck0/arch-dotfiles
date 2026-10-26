#!/bin/bash
# project diablo 2's dll checks that its own dir sits inside a lord of destruction install, hence the cwd
cd "@game@" || exit 1
export WINEPREFIX="@prefix@" WINEDLLOVERRIDES="ddraw=n,b" PIPEWIRE_ALSA='{ application.name="Project Diablo II" }'
# the fastest output's rate at launch, not at apply time (an apply from a tty sees no hyprland)
refresh=$(hyprctl -j monitors 2> /dev/null | jq -r '[.[] | select(.name | test("^HEADLESS-") | not) | .refreshRate] | max // 60 | round')
# shellcheck disable=SC2016
exec gamescope -w @width@ -h @height@ -r "${refresh:-60}" -S fit -F linear -- \
    sh -c '"$1/wine" start /wait /unix "$2"; "$1/wineserver" -w' sh "@wine@" "@exe@"
