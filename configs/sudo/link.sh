#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v visudo >/dev/null 2>&1; then
    exit 0
fi

set -ex

# Validate before installing so a bad edit can never lock out sudo. Symlinks are
# not usable in /etc/sudoers.d (sudo requires root:root 0440), so copy it.
if sudo visudo -cf 00_luca; then
    sudo install -m440 -o root -g root 00_luca /etc/sudoers.d/00_luca
fi
# Drop the old passwordless drop-in if a previous install created it.
sudo rm -f "/etc/sudoers.d/10-${USER}-nopasswd"
