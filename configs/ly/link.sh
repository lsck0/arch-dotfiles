#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

# ly's binary is ly-dm (the `ly` package ships no `ly` command)
if ! command -v ly-dm >/dev/null 2>&1; then
    exit 0
fi

set -ex

# ly runs at boot before /home is mounted, so install a real file in /etc
config=/etc/ly/config.ini
backup="${config}.arch-dotfiles-backup"
if [[ -e "$config" && ! -e "$backup" ]]; then
    sudo install -Dm644 "$config" "$backup"
fi

sudo install -Dm644 config.ini "$config"
