#!/usr/bin/env bash
# the per-user profile replaced the luca username check: a login with a template in profiles/ gets it once, a guest stays without
set -euo pipefail

source "$DOTFILES/scripts/lib/profile.sh"
template="$DOTFILES/profiles/$(id -un).sh"

[[ -e "$PROFILE_FILE" || ! -f "$template" ]] || install -Dm644 "$template" "$PROFILE_FILE"
