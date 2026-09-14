#!/usr/bin/env bash
# Portmaster runs its filtering as portmaster.service (systemd, always on --
# that's the actual firewall). The package additionally ships an XDG
# autostart entry (/etc/xdg/autostart/portmaster-autostart.desktop) that
# spawns the Electron/Tauri UI+notifier on every login -- separate from the
# service, and the thing the user actually wants off by default. XDG
# autostart precedence lets a user-level ~/.config/autostart/<name>.desktop
# with the same filename override/disable the system one (freedesktop.org
# Desktop Application Autostart Spec) without touching the package's own
# file, so this survives a portmaster package upgrade.
if [[ ! -f ${PWD}/config.json ]]; then
    exit 0
fi

set -ex

sudo ln -sf ${PWD}/config.json /var/lib/portmaster/config.json

if [[ -f /etc/xdg/autostart/portmaster-autostart.desktop ]]; then
    mkdir -p "${HOME}/.config/autostart"
    ln -sf "${PWD}/portmaster-autostart.desktop" "${HOME}/.config/autostart/portmaster-autostart.desktop"
fi
