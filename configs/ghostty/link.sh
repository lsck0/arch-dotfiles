#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v ghostty >/dev/null 2>&1; then
    exit 0
fi

set -e

ln -sfn "${PWD}" "$HOME/.config/ghostty"

dropin="${HOME}/.config/systemd/user/app-com.mitchellh.ghostty.service.d"
mkdir -p "$dropin"
ln -sfn "${PWD}/systemd/override.conf" "${dropin}/override.conf"
systemctl --user daemon-reload
systemctl --user reset-failed app-com.mitchellh.ghostty.service 2>/dev/null || true
