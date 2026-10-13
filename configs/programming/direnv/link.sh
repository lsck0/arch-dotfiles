#!/usr/bin/env bash

# install.sh puts devenv in the nix profile, which may not be on PATH yet
DEVENV="$(command -v devenv || echo "${HOME}/.nix-profile/bin/devenv")"
if ! command -v direnv >/dev/null 2>&1 || [[ ! -x "$DEVENV" ]]; then
    exit 0
fi

# rendered, then copied through file_update: a direnvrc written by hand is kept aside, never overwritten
tmp=$(mktemp)
"$DEVENV" direnvrc >"$tmp"
file_update "$tmp" "${HOME}/.config/direnv/direnvrc" || true
rm -f "$tmp"
