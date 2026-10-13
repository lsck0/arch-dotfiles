#!/usr/bin/env bash
# remote luks unlock: a tinyssh server in the systemd initramfs (mkinitcpio-systemd-tool) so the root disk unlocks over
# the network — wake-on-lan the box, ssh into early boot, answer the passphrase prompt, boot continues. the on-console
# passphrase/yubikey prompt is untouched and stays the local fallback, so a broken setup never bricks boot.
# opt in per machine with REMOTE_UNLOCK=1 (platforms/*.sh) plus the packages in EXTRA_PACKAGES; a no-op, and self-undoing, otherwise.
set -euo pipefail

source "$DOTFILES/configs/base/boot/common.sh"

HOOK=systemd-tool
TOOLCONF=/etc/mkinitcpio-systemd-tool/mkinitcpio-systemd-tool.conf
NETWORK=/etc/mkinitcpio-systemd-tool/network/initrd-network.network
KEYDIR=/etc/tinyssh/sshkeydir
UNITS=(initrd-network.service initrd-tinysshd.service)
SECRET_DIR="$DOTFILES/secrets/initramfs-ssh/$(uname -n)"
PUBKEY="$DOTFILES/secrets/ssh_publickey.asc"

hook_drop() {
    [[ -f /etc/mkinitcpio.conf ]] || return 0
    python - "$HOOK" <<'PY'
import re, sys
from pathlib import Path
hook = sys.argv[1]
p = Path("/etc/mkinitcpio.conf"); s = p.read_text()
m = re.search(r'^HOOKS=\((.*)\)', s, re.MULTILINE)
if not m or hook not in m.group(1).split(): raise SystemExit(0)
hooks = [h for h in m.group(1).split() if h != hook]
p.write_text(s[:m.start(1)] + " ".join(hooks) + s[m.end(1):])
PY
}

# dropping the fact removes the wiring, so a reused machine stops exposing an initramfs ssh
if [[ -z "${REMOTE_UNLOCK:-}" ]]; then
    if systemctl is-enabled initrd-tinysshd.service >/dev/null 2>&1 \
        || grep -qE "^HOOKS=\(.*\b${HOOK}\b" /etc/mkinitcpio.conf 2>/dev/null; then
        systemctl disable "${UNITS[@]}" 2>/dev/null || true
        rm -rf "$UNIT_DIR/initrd-tinysshd.service.d"
        hook_drop
        kernel_cmdline_unset rd.neednet
        echo "remote-unlock: REMOTE_UNLOCK unset, initramfs ssh wiring removed" >&2
    fi
    exit 0
fi

if ! command -v tinysshd >/dev/null 2>&1 || [[ ! -f /usr/lib/initcpio/install/systemd-tool ]]; then
    echo "remote-unlock: needs mkinitcpio-systemd-tool + tinyssh + tinyssh-convert + busybox (add to EXTRA_PACKAGES)" >&2
    exit 0
fi

# dedicated per-host initramfs host key, separate from the system's /etc/ssh key: from secrets, else generated once and
# the admin backs it up. tinyssh is ed25519-only
if [[ -f "$SECRET_DIR/sshkeydir/.ed25519.sk" ]]; then
    rm -rf "$KEYDIR"
    install -dm700 "$(dirname "$KEYDIR")"
    cp -a "$SECRET_DIR/sshkeydir" "$KEYDIR"
    chmod 700 "$KEYDIR"
elif [[ ! -f "$KEYDIR/.ed25519.sk" ]]; then
    install -dm700 "$(dirname "$KEYDIR")"
    tinysshd-makekey "$KEYDIR"
    echo "remote-unlock: generated a new initramfs host key; back it up and commit: mkdir -p '$SECRET_DIR' && cp -a '$KEYDIR' '$SECRET_DIR/sshkeydir'" >&2
fi

# use that key and do not reconvert the system host key at build time
file_update "$PWD/mkinitcpio-systemd-tool.conf" "$TOOLCONF" || true
# the wired nic by wildcard, dhcp (its reservation gives a stable address); the stock file matches eth* only
file_update "$PWD/initrd-network.network" "$NETWORK" || true

# tinysshd authenticates root (the only initramfs user) against /root/.ssh/authorized_keys; the running sshd denies root
# login (configs/base/ssh/10-hardening.conf PermitRootLogin no), so this key is inert outside the initramfs
if command -v secret_is_plaintext >/dev/null 2>&1 && secret_is_plaintext "$PUBKEY" || grep -q '^ssh-' "$PUBKEY" 2>/dev/null; then
    install -dm700 /root/.ssh
    install -m600 "$PUBKEY" /root/.ssh/authorized_keys
else
    echo "remote-unlock: secrets/ssh_publickey.asc not readable, unlock the secrets and rerun; no authorized_keys installed" >&2
fi
# login shell runs the password agent only in the initramfs (/etc/initrd-release), a no-op on the real system
install -m644 "$PWD/root-profile" /root/.profile

# port + the two paths the initramfs needs; the install hook reads X-SystemdTool from drop-ins too
dropin_install initrd-tinysshd.service tinysshd.conf || true

# the units carry ConditionPathExists=/etc/initrd-release, so enabling them never starts them on the running system; the
# enable symlinks are what the systemd-tool install hook scans to include them in the initramfs
systemctl enable "${UNITS[@]}" >/dev/null 2>&1 || true

# place the hook after sd-encrypt so the cryptsetup machinery it feeds is already present
if [[ -f /etc/mkinitcpio.conf ]]; then
    python - "$HOOK" <<'PY'
import re, sys
from pathlib import Path
hook = sys.argv[1]
p = Path("/etc/mkinitcpio.conf"); s = p.read_text()
m = re.search(r'^HOOKS=\((.*)\)', s, re.MULTILINE)
if not m: sys.exit("remote-unlock: no HOOKS=( line in mkinitcpio.conf")
hooks = m.group(1).split()
if hook in hooks: raise SystemExit(0)
anchor = "sd-encrypt" if "sd-encrypt" in hooks else ("filesystems" if "filesystems" in hooks else None)
if anchor is None: sys.exit("remote-unlock: no sd-encrypt/filesystems hook to anchor systemd-tool")
pos = hooks.index(anchor) + (1 if anchor == "sd-encrypt" else 0)
hooks.insert(pos, hook)
p.write_text(s[:m.start(1)] + " ".join(hooks) + s[m.end(1):])
print("remote-unlock: added systemd-tool hook to mkinitcpio.conf", file=sys.stderr)
PY
fi

# bring the network up early so tinysshd can bind before the cryptsetup prompt
kernel_cmdline_set rd.neednet=1

echo "remote-unlock: initramfs ssh on port 2223 configured; the local passphrase prompt remains the fallback" >&2
