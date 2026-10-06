#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

# @USER@ filled with the live login, so a guest gets working sudo for their own user
rendered=$(sed "s|@USER@|$(id -un)|g" 00_user)
# validate first; sudoers.d needs a root:root 0440 copy, not a symlink
if echo "$rendered" | sudo visudo -cf -; then
    echo "$rendered" | sudo install -m440 -o root -g root /dev/stdin /etc/sudoers.d/00_user
fi
# drop the old hardcoded-luca name and the legacy passwordless drop-in
sudo rm -f /etc/sudoers.d/00_luca "/etc/sudoers.d/10-$(id -un)-nopasswd"
