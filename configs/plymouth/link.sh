#!/usr/bin/env bash

set -euo pipefail

# Minimal, reversible Plymouth setup. This selects the packaged spinner theme
# and adds only Plymouth's initcpio hook; it does not touch Limine, partitions,
# or bootloader installation.
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
