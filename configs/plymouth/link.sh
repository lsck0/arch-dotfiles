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
import sys
from pathlib import Path

p = Path('/etc/mkinitcpio.conf')
s = p.read_text()
m = re.search(r'^HOOKS=\((.*)\)$', s, re.MULTILINE)
if not m:
    sys.exit('plymouth: no HOOKS=(...) line in /etc/mkinitcpio.conf')

hooks = m.group(1).split()
wanted = 'sd-plymouth' if 'systemd' in hooks else 'plymouth'
if 'plymouth' not in hooks and 'sd-plymouth' not in hooks:
    anchor = next((h for h in ('kms', 'systemd', 'udev', 'base') if h in hooks), None)
    if anchor is None:
        sys.exit('plymouth: HOOKS has no kms/systemd/udev/base to insert after')
    hooks.insert(hooks.index(anchor) + 1, wanted)
    s = s[:m.start()] + 'HOOKS=(%s)' % ' '.join(hooks) + s[m.end():]
    p.write_text(s)
    print('plymouth: added %s after %s' % (wanted, anchor))
PY

sudo plymouth-set-default-theme spinner

cmdline=/etc/kernel/cmdline
if [[ ! -f "$cmdline" ]]; then
    seed="$(tr ' ' '\n' < /proc/cmdline | grep -vE '^(BOOT_IMAGE|initrd)=' | paste -sd' ')"
    printf '%s\n' "$seed" | sudo tee "$cmdline" >/dev/null
    sudo chmod 644 "$cmdline"
fi

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
