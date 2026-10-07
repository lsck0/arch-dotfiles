#!/usr/bin/env bash

source "$DOTFILES/configs/hardware/boot/boot-menu/common.sh"

theme=cyberpunk
install -d "/usr/share/plymouth/themes/$theme"
install -m644 "theme/$theme"/*.{plymouth,script,png} "/usr/share/plymouth/themes/$theme/"

config=/etc/mkinitcpio.conf
backup="${config}.arch-dotfiles-backup"
if [[ ! -e "$backup" ]]; then
    install -Dm644 "$config" "$backup"
fi

python - <<'PY'
import re
import sys
from pathlib import Path

p = Path('/etc/mkinitcpio.conf')
s = p.read_text()
m = re.search(r'^HOOKS=\((.*)\)$', s, re.MULTILINE)
if not m:
    sys.exit('plymouth: no HOOKS=(...) line in /etc/mkinitcpio.conf')

hooks = m.group(1).split()
# plymouth 24 dropped sd-plymouth, the plain hook covers systemd initramfs too; migrate old configs
hooks = ['plymouth' if h == 'sd-plymouth' else h for h in hooks]
if 'plymouth' not in hooks:
    anchor = next((h for h in ('kms', 'systemd', 'udev', 'base') if h in hooks), None)
    if anchor is None:
        sys.exit('plymouth: HOOKS has no kms/systemd/udev/base to insert after')
    hooks.insert(hooks.index(anchor) + 1, 'plymouth')
    print('plymouth: added plymouth after %s' % anchor)
new = s[:m.start()] + 'HOOKS=(%s)' % ' '.join(hooks) + s[m.end():]
if new != s:
    p.write_text(new)
PY

plymouth-set-default-theme "$theme"

# quiet splash drive plymouth; the cursor is hidden on ly's tty only, a global one would hide it on recovery ttys too
if esp_supported; then
    kernel_cmdline_set quiet splash
    kernel_cmdline_unset vt.global_cursor_default
fi

# hooks, theme and cmdline reach the uki at system-apply's boot barrier
