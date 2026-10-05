#!/usr/bin/env bash
# root unlocks with an enrolled yubikey (fido2 pin + touch); without the key the passphrase prompt follows after token-timeout (30 s)

set -e

MARKER="# MARKER:arch-dotfiles/boot/luks"
CRYPTTAB="/etc/crypttab"

mapfile -t LUKS_PARTS < <(lsblk -ln -o NAME,UUID,FSTYPE,TYPE | awk '$3 == "crypto_LUKS" && $4 == "part" {print $1, $2}')

if [[ ${#LUKS_PARTS[@]} -eq 0 ]]; then
    echo "luks: no LUKS-encrypted partitions detected, nothing to configure" >&2
    exit 0
fi

# the root device must not go in crypttab
ROOT_SRC="$(findmnt -n -o SOURCE /)"
ROOT_SRC="${ROOT_SRC%%[*}"
ROOT_BACKING=""
if [[ "$ROOT_SRC" == /dev/mapper/* ]]; then
    ROOT_BACKING="$(lsblk -lnso NAME,TYPE "$ROOT_SRC" | awk '$2 == "part" {print $1; exit}')"
fi

# back up a crypttab we do not manage yet
sudo mkdir -p "$(dirname "$CRYPTTAB")"
if [[ -f "$CRYPTTAB" ]]; then
    if ! sudo grep -qF "$MARKER" "$CRYPTTAB"; then
        sudo install -m644 "$CRYPTTAB" "${CRYPTTAB}.arch-dotfiles-backup"
    fi
fi
if [[ ! -f "$CRYPTTAB" ]]; then
    sudo install -m644 "$(dirname "$0")/crypttab" "$CRYPTTAB"
fi
# drop the managed block of a prior run, marker to eof
sudo sed -i "\|^$MARKER\$|,\$d" "$CRYPTTAB" # marker has slashes
sudo sed -i -e '$a\' "$CRYPTTAB"
echo "$MARKER" | sudo tee -a "$CRYPTTAB" >/dev/null

added=0
for entry in "${LUKS_PARTS[@]}"; do
    part="${entry%% *}"
    uuid="${entry##* }"
    [[ -z "$uuid" || "$uuid" == "$part" ]] && continue
    if [[ -n "$ROOT_BACKING" && "$part" == "$ROOT_BACKING" ]]; then
        continue
    fi
    name="luks-${uuid}"
    if sudo grep -qE "^${name}\s" "$CRYPTTAB"; then
        continue
    fi
    printf '%s\tUUID=%s\tnone\tluks,discard,perf-no-read-workqueue,perf-no-write-workqueue\n' \
        "$name" "$uuid" | sudo tee -a "$CRYPTTAB" >/dev/null
    added=$(( added + 1 ))
done

# encrypt hook must precede filesystems
CONF="/etc/mkinitcpio.conf"
if [[ -f "$CONF" ]]; then
    if grep -qE 'HOOKS=\(.*\bencrypt\b' "$CONF"; then
        echo "luks: encrypt hook already in mkinitcpio.conf" >&2
    elif grep -qE 'HOOKS=\(.*\bsd-encrypt\b' "$CONF"; then
        echo "luks: sd-encrypt hook already in mkinitcpio.conf" >&2
    elif grep -qE 'HOOKS=\(.*\bsystemd\b' "$CONF"; then
        echo "luks: systemd hook present, encrypt handled by systemd-cryptsetup in initrd" >&2
    else
        echo "luks: adding encrypt hook before filesystems in mkinitcpio.conf" >&2
        if [[ ! -e "${CONF}.arch-dotfiles-backup" ]]; then
            sudo install -Dm644 "$CONF" "${CONF}.arch-dotfiles-backup"
        fi
        sudo python - <<'PY'
import sys
from pathlib import Path
p = Path("/etc/mkinitcpio.conf")
s = p.read_text()
if "HOOKS=(" not in s:
    sys.exit("luks: no HOOKS=( line in mkinitcpio.conf, refusing to guess")
i = s.index("HOOKS=(")
j = s.index(")", i) + 1
block = s[i:j]
if "encrypt" in block or "systemd" in block:
    sys.exit(0)
if "filesystems" not in block:
    sys.exit("luks: HOOKS has no `filesystems` hook, refusing to place `encrypt`")
if "block" not in block:
    sys.exit("luks: HOOKS has no `block` hook, `encrypt` would have no device")
if "keyboard" not in block:
    sys.exit("luks: HOOKS has no `keyboard` hook, passphrase entry would be impossible")
p.write_text(s[:i] + block.replace("filesystems", "encrypt filesystems", 1) + s[j:])
PY
    fi
fi

# sd-encrypt ships the fido2 token plugin; with no token enrolled systemd-cryptsetup falls through to the passphrase or stage.sh's keyfile
if [[ -n "$ROOT_BACKING" ]]; then
    source "$(dirname "$0")/../boot-menu/common.sh"
    kernel_cmdline_set rd.luks.options=fido2-device=auto
    # enrolling during the stage chain would make its unattended boots wait for a touch
    if ! sudo cryptsetup luksDump "/dev/$ROOT_BACKING" | grep -q systemd-fido2; then
        echo "luks: no yubikey enrolled, once the stage chain is done: sudo systemd-cryptenroll --fido2-device=auto /dev/$ROOT_BACKING" >&2
    fi
fi

# the encrypt hook lands in the initramfs at config.sh's boot barrier
echo "luks: crypttab configured, $added non-root LUKS volume(s) added" >&2
