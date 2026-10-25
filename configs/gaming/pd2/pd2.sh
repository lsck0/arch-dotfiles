#!/bin/bash
# project diablo 2's dll checks that its own dir sits inside a lord of destruction install, hence the cwd
cd "@game@" || exit 1
export WINEPREFIX="@prefix@" WINEDLLOVERRIDES="ddraw=n,b" PIPEWIRE_ALSA='{ application.name="Project Diablo II" }'
# shellcheck disable=SC2016
exec gamescope -w @width@ -h @height@ -r @refresh@ -S fit -F linear -- \
    sh -c '"$1/wine" start /wait /unix PlugY.exe; "$1/wineserver" -w' sh "@wine@"
