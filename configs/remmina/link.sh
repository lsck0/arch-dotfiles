#!/usr/bin/env bash

if ! command -v flatpak >/dev/null 2>&1; then
    exit 0
fi

set -ex

AUTOSTART="${HOME}/.config/autostart/remmina-applet.desktop"

# user scope, not the sudo FLATPAK_PKGS batch
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user -y flathub org.remmina.Remmina

# remmina recreates a missing autostart, so hide it
mkdir -p "$(dirname "$AUTOSTART")"
if [[ -f "$AUTOSTART" ]]; then
    sed -i 's/^Hidden=.*/Hidden=true/' "$AUTOSTART"
    grep -q '^Hidden=' "$AUTOSTART" || echo 'Hidden=true' >>"$AUTOSTART"
else
    printf '[Desktop Entry]\nType=Application\nName=Remmina Applet\nExec=flatpak run org.remmina.Remmina -i\nHidden=true\n' >"$AUTOSTART"
fi
