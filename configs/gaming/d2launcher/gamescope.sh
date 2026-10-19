#!/bin/bash
# "Diablo II.exe" hands off to Game.exe and exits, and gamescope stops with its first child: wait for the wineserver
cd "@game@" || exit 1
# winealsa reaches pipewire through pipewire-alsa, which names the stream only from PIPEWIRE_ALSA
export WINEPREFIX="@prefix@" PIPEWIRE_ALSA='{ application.name="Diablo II" }'
# shellcheck disable=SC2016
exec gamescope -w @width@ -h @height@ -S fit -F linear -- \
    sh -c '"$1/wine" start /wait /unix "$2" @args@; "$1/wineserver" -w' sh "@wine@" "@exe@"
