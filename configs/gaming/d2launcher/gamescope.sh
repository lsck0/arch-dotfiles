#!/bin/bash
cd "@game@" || exit 1
export WINEPREFIX="@prefix@" PIPEWIRE_ALSA='{ application.name="Diablo II" }'
# shellcheck disable=SC2016
exec gamescope -w @width@ -h @height@ -r @refresh@ -S fit -F linear -- \
    sh -c '"$1/wine" start /wait /unix "$2" @args@; "$1/wineserver" -w' sh "@wine@" "@exe@"
