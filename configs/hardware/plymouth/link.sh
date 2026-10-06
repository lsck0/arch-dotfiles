#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

source ../../hardware/boot/boot-menu/common.sh

theme=cyberpunk
sudo install -d /usr/share/plymouth/themes/"$theme"
sudo install -Dm644 "${PWD}/theme/$theme"/*.{plymouth,script,png} /usr/share/plymouth/themes/"$theme"/

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

sudo plymouth-set-default-theme "$theme"

# quiet splash drive plymouth; vt.global_cursor_default=0 stops the text cursor flashing on the vt during the plymouth-to-ly handoff
if esp_supported; then
    kernel_cmdline_set quiet splash vt.global_cursor_default=0
fi

# hooks, theme and cmdline reach the initramfs and grub.cfg at config.sh's boot barrier
