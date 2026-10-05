#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v ghostty >/dev/null 2>&1; then
    exit 0
fi

set -e

ln -sfn "${PWD}" "$HOME/.config/ghostty"
# volatile like tlp's forced mode, so a reboot never leaves power-saver tweaks behind
mkdir -p "$HOME/.cache"
ln -sfn "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/toggles/ghostty-powersave.conf" "$HOME/.cache/ghostty-powersave.conf"

dropin="${HOME}/.config/systemd/user/app-com.mitchellh.ghostty.service.d"
mkdir -p "$dropin"
ln -sfn "${PWD}/systemd/override.conf" "${dropin}/override.conf"
systemctl --user daemon-reload
# not loaded yet on a first run, then there is nothing to reset
systemctl --user reset-failed app-com.mitchellh.ghostty.service 2>/dev/null || true
# prewarm at login, windows open over d-bus via ghostty +new-window
systemctl --user enable app-com.mitchellh.ghostty.service
