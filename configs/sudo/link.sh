#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v visudo >/dev/null 2>&1; then
    exit 0
fi

set -ex

# validate first; sudoers.d needs a root:root 0440 copy, not a symlink
if sudo visudo -cf 00_luca; then
    sudo install -m440 -o root -g root 00_luca /etc/sudoers.d/00_luca
fi
# legacy passwordless drop-in
sudo rm -f "/etc/sudoers.d/10-${USER}-nopasswd"
