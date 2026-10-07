#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

user=$(id -un)
# one drop-in per user, so a guest's run never rewrites luca's grant; sudo skips sudoers.d names containing a dot
drop_in="/etc/sudoers.d/00_${user//./_}"
rendered=$(sed "s|@USER@|$user|g" 00_user)
# validate first; sudoers.d needs a root:root 0440 copy, not a symlink
if echo "$rendered" | sudo visudo -cf -; then
    echo "$rendered" | sudo install -m440 -o root -g root /dev/stdin "$drop_in"
    # the old shared name only goes once it is this user's own grant, now duplicated above
    if sudo grep -qE "^$user[[:space:]]" /etc/sudoers.d/00_user 2>/dev/null; then
        sudo rm -f /etc/sudoers.d/00_user
    fi
fi
sudo rm -f "/etc/sudoers.d/10-$user-nopasswd"
