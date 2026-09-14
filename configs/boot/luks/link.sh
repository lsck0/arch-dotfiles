#!/usr/bin/env bash
# LUKS / dm-crypt provisioning.
# Idempotent. Detects existing LUKS-encrypted devices and configures
# /etc/crypttab options + ensures the mkinitcpio encrypt hook is present.
# Does NOT migrate a non-encrypted root into LUKS — that is a manual,
# point-of-no-return step (fresh install or btrfs send/receive from backup);
# see README §Boot disk security + BOOT.md §Execution sequence.
set -euo pipefail

BOOT_STATE="$HOME/projects/arch-dotfiles/boot.conf"
if [[ ! -f "$BOOT_STATE" ]] || ! grep -qx luks "$BOOT_STATE"; then
    exit 0
fi

MARKER="# MARKER:arch-dotfiles/boot/luks"
CRYPTTAB="/etc/crypttab"

# Detect LUKS partition backends (not the mapped devices themselves).
#
# `-l`, not the default tree output. Plain `lsblk -n` draws the hierarchy with
# box-drawing glyphs in the NAME column, so a partition came back as
# "├─nvme0n1p2" and that string was what got written into /etc/crypttab as the
# mapper name — an entry naming a device that cannot exist.
mapfile -t LUKS_PARTS < <(lsblk -ln -o NAME,UUID,FSTYPE,TYPE 2>/dev/null \
    | awk '$3 == "crypto_LUKS" && $4 == "part" {print $1, $2}' || true)

if [[ ${#LUKS_PARTS[@]} -eq 0 ]]; then
    echo "luks: no LUKS-encrypted partitions detected — nothing to configure" >&2
    exit 0
fi

# THE ROOT DEVICE MUST NOT GO IN CRYPTTAB.
#
# Root is unlocked in the initramfs, by the encrypt hook from the kernel
# cmdline's cryptdevice= (or by sd-encrypt/systemd-cryptsetup). By the time
# /etc/crypttab is processed the mapping is already open, and a second entry for
# the same backing device asks systemd-cryptsetup to open it again under a
# different name: at best a redundant passphrase prompt on every boot, at worst
# a 90-second job timeout blocking local-fs.target on the device the whole
# system is mounted from. crypttab is for the NON-root volumes.
ROOT_SRC="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
ROOT_BACKING=""
if [[ "$ROOT_SRC" == /dev/mapper/* ]]; then
    ROOT_BACKING="$(lsblk -no pkname "$ROOT_SRC" 2>/dev/null | head -1 || true)"
fi

# Ensure crypttab header + marker exist, back up a pre-existing live file.
sudo mkdir -p "$(dirname "$CRYPTTAB")"
if [[ -f "$CRYPTTAB" ]]; then
    if ! sudo grep -qF "$MARKER" "$CRYPTTAB" 2>/dev/null; then
        sudo install -m644 "$CRYPTTAB" "${CRYPTTAB}.arch-dotfiles-backup" 2>/dev/null || true
    fi
fi
if [[ ! -f "$CRYPTTAB" ]]; then
    sudo install -m644 "$(dirname "$0")/crypttab" "$CRYPTTAB"
else
    # Strip any auto-appended entries from a prior run so we can rewrite cleanly.
    if sudo grep -qF "$MARKER" "$CRYPTTAB" 2>/dev/null; then
        sudo sed -i "/^$MARKER$/,\$d" "$CRYPTTAB"
    fi
    # Only the live file. `sed -i` edits every path it is given, so passing the
    # repo's template alongside it rewrote a tracked file in the checkout —
    # under sudo, leaving it root-owned. All this needs is a trailing newline on
    # /etc/crypttab so the appends below start on a line of their own.
    sudo sed -i -e '$a\' "$CRYPTTAB"
fi

# Append one entry per non-root LUKS partition, idempotent per mapper name.
#
# The mapper name is `luks-<uuid>`, the name systemd-cryptsetup-generator and
# the desktop stack already use for a crypttab-managed volume. Naming the
# mapping after the partition (`nvme0n1p3`) produced /dev/mapper/nvme0n1p3,
# which reads like a partition node and collides with nothing useful.
added=0
for entry in "${LUKS_PARTS[@]}"; do
    part="${entry%% *}"
    uuid="${entry##* }"
    [[ -z "$uuid" || "$uuid" == "$part" ]] && continue
    if [[ -n "$ROOT_BACKING" && "$part" == "$ROOT_BACKING" ]]; then
        echo "luks: $part backs the root mount — left to the initramfs, not crypttab" >&2
        continue
    fi
    name="luks-${uuid}"
    if sudo grep -qE "^${name}\s" "$CRYPTTAB" 2>/dev/null; then
        continue
    fi
    printf '%s\tUUID=%s\tnone\tluks,discard,perf-no-read-workqueue,perf-no-write-workqueue\n' \
        "$name" "$uuid" | sudo tee -a "$CRYPTTAB" >/dev/null
    added=$(( added + 1 ))
done
echo "$MARKER" | sudo tee -a "$CRYPTTAB" >/dev/null

# mkinitcpio: ensure the encrypt hook is present before filesystems.
CONF="/etc/mkinitcpio.conf"
if [[ -f "$CONF" ]]; then
    if grep -qE 'HOOKS=\(.*\bencrypt\b' "$CONF"; then
        echo "luks: encrypt hook already in mkinitcpio.conf" >&2
    elif grep -qE 'HOOKS=\(.*\bsd-encrypt\b' "$CONF"; then
        echo "luks: sd-encrypt hook already in mkinitcpio.conf" >&2
    elif grep -qE 'HOOKS=\(.*\bsystemd\b' "$CONF"; then
        echo "luks: systemd hook present — encrypt handled by systemd-cryptsetup in initrd" >&2
    else
        echo "luks: adding encrypt hook before filesystems in mkinitcpio.conf" >&2
        # Back up before editing the file the machine boots from, the same way
        # configs/plymouth/link.sh does. A HOOKS line this script got wrong is
        # recoverable from a live USB either way, but only if the original is
        # still on disk to compare against.
        if [[ ! -e "${CONF}.arch-dotfiles-backup" ]]; then
            sudo install -Dm644 "$CONF" "${CONF}.arch-dotfiles-backup"
        fi
        sudo python - <<'PY'
import sys
from pathlib import Path
p = Path("/etc/mkinitcpio.conf")
s = p.read_text()
if "HOOKS=(" not in s:
    sys.exit("luks: no HOOKS=( line in mkinitcpio.conf — refusing to guess")
i = s.index("HOOKS=(")
j = s.index(")", i) + 1
block = s[i:j]
if "encrypt" in block or "systemd" in block:
    sys.exit(0)
# `encrypt` goes immediately before `filesystems`, and needs `block` earlier for
# the device node plus `keyboard`/`keymap` earlier for a passphrase that can
# actually be typed on a non-US layout. Bail rather than write a HOOKS line that
# produces an initramfs which cannot unlock the disk it is about to require.
if "filesystems" not in block:
    sys.exit("luks: HOOKS has no `filesystems` hook — refusing to place `encrypt`")
if "block" not in block:
    sys.exit("luks: HOOKS has no `block` hook — `encrypt` would have no device")
if "keyboard" not in block:
    sys.exit("luks: HOOKS has no `keyboard` hook — passphrase entry would be impossible")
p.write_text(s[:i] + block.replace("filesystems", "encrypt filesystems", 1) + s[j:])
PY
    fi
fi

# Rebuild initramfs so crypttab-backed devices are recognized at boot.
#
# NOT `|| true`, and stderr is not discarded. This is the step that decides
# whether the machine boots; a build that fails here has to be loud, and the
# non-zero exit propagates to install.sh's FAILURES list instead of printing
# "crypttab configured" over the top of a broken initramfs.
if command -v mkinitcpio >/dev/null 2>&1; then
    sudo mkinitcpio -P
fi

echo "luks: crypttab configured, $added non-root LUKS volume(s) added" >&2
