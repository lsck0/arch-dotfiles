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
import re
from pathlib import Path
p = Path('/etc/mkinitcpio.conf')
s = p.read_text()
# Match only the live HOOKS=(...) line, not the commented examples above it.
m = re.search(r'^HOOKS=\((.*)\)$', s, re.MULTILINE)
if m and ' plymouth' not in m.group(1).split():
    hooks = m.group(0)
    new_hooks = hooks.replace(' kms ', ' kms plymouth ', 1)
    s = s[:m.start()] + new_hooks + s[m.end():]
    p.write_text(s)
PY

sudo plymouth-set-default-theme spinner

cmdline=/etc/kernel/cmdline
if [[ -f "$cmdline" ]]; then
    cmdline_backup="${cmdline}.arch-dotfiles-backup"
    if [[ ! -e "$cmdline_backup" ]]; then
        sudo install -Dm644 "$cmdline" "$cmdline_backup"
    fi
    current="$(cat "$cmdline")"
    words=" $current "
    for w in quiet splash; do
        [[ "$words" == *" $w "* ]] || current="$current $w"
    done
    if [[ "$current" != "$(cat "$cmdline")" ]]; then
        printf '%s\n' "$current" | sudo tee "$cmdline" >/dev/null
    fi
fi

sudo mkinitcpio -P
