#!/usr/bin/env bash

if ! command -v plymouth-set-default-theme >/dev/null 2>&1; then
    exit 0
fi

set -ex

config=/etc/mkinitcpio.conf
backup="${config}.arch-dotfiles-backup"
if [[ ! -e "$backup" ]]; then
    sudo install -Dm644 "$config" "$backup"
fi

sudo python - <<'PY'
from pathlib import Path
p = Path('/etc/mkinitcpio.conf')
s = p.read_text()
if ' plymouth ' not in s and 'HOOKS=(' in s:
    start = s.index('HOOKS=(')
    end = s.index(')', start) + 1
    hooks = s[start:end]
    s = s[:start] + hooks.replace(' kms ', ' kms plymouth ', 1) + s[end:]
    p.write_text(s)
PY

sudo plymouth-set-default-theme spinner
sudo mkinitcpio -P
