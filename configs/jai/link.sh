#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source ../../scripts/lib/personal.sh
is_personal || exit 0

GROUPS_STATE="$HOME/projects/arch-dotfiles/groups.conf"
if [[ ! -f "$GROUPS_STATE" ]] || ! grep -qx programming "$GROUPS_STATE"; then
    exit 0
fi

set -e

source ../../scripts/lib/user-hook.sh
user_hook_install ./hook jai-install
