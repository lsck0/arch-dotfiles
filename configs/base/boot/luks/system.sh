#!/usr/bin/env bash
# root unlocks with an enrolled yubikey (fido2 pin + touch); without the key the passphrase prompt follows after token-timeout (30 s)

MARKER="# MARKER:arch-dotfiles/boot/luks"
CRYPTTAB="/etc/crypttab"
# PCR 15 before any volume key is measured into it
PCR15_INITIAL=0000000000000000000000000000000000000000000000000000000000000000

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
if [[ -f "$CRYPTTAB" ]]; then
    if ! grep -qF "$MARKER" "$CRYPTTAB"; then
        install -m644 "$CRYPTTAB" "${CRYPTTAB}.arch-dotfiles-backup"
    fi
else
    install -Dm644 crypttab "$CRYPTTAB"
fi
# drop the managed block of a prior run, marker to eof
sed -i "\|^$MARKER\$|,\$d" "$CRYPTTAB" # marker has slashes
sed -i -e '$a\' "$CRYPTTAB"
echo "$MARKER" >>"$CRYPTTAB"

added=0
for entry in "${LUKS_PARTS[@]}"; do
    part="${entry%% *}"
    uuid="${entry##* }"
    [[ -z "$uuid" || "$uuid" == "$part" ]] && continue
    if [[ -n "$ROOT_BACKING" && "$part" == "$ROOT_BACKING" ]]; then
        continue
    fi
    # usb sticks and external drives come and go, they get no permanent entry
    disk=$(lsblk -dno PKNAME "/dev/$part")
    [[ "$(lsblk -dno RM,HOTPLUG "/dev/$disk" | tr -d ' ')" == 00 ]] || continue
    name="luks-${uuid}"
    if grep -qE "^${name}\s" "$CRYPTTAB"; then
        continue
    fi
    # nofail: a missing or locked data volume must not hold up the boot
    printf '%s\tUUID=%s\tnone\tluks,nofail,discard,perf-no-read-workqueue,perf-no-write-workqueue\n' \
        "$name" "$uuid" >>"$CRYPTTAB"
    added=$(( added + 1 ))
done

# encrypt hook must precede filesystems
CONF="/etc/mkinitcpio.conf"
if [[ -f "$CONF" ]]; then
    python - <<'PY'
import re
import sys
from pathlib import Path
p = Path("/etc/mkinitcpio.conf")
s = p.read_text()
# the live line only: the stock file's commented HOOKS=( examples name encrypt too
m = re.search(r'^HOOKS=\((.*)\)', s, re.MULTILINE)
if not m:
    sys.exit("luks: no HOOKS=( line in mkinitcpio.conf, refusing to guess")
hooks = m.group(1).split()
# rd.luks.options=fido2-device=auto is read by systemd-cryptsetup alone: sd-encrypt in a systemd initramfs, the busybox
# encrypt only where there is none
hook = "sd-encrypt" if "systemd" in hooks else "encrypt"
present = [h for h in ("sd-encrypt", "encrypt") if h in hooks]
if present:
    print(f"luks: {present[0]} hook already in mkinitcpio.conf", file=sys.stderr)
    if "sd-encrypt" not in present:
        print("luks: busybox encrypt ignores rd.luks.options, the yubikey unlock needs the systemd and sd-encrypt hooks",
              file=sys.stderr)
    sys.exit(0)
if "filesystems" not in hooks:
    sys.exit(f"luks: HOOKS has no `filesystems` hook, refusing to place `{hook}`")
if "block" not in hooks:
    sys.exit(f"luks: HOOKS has no `block` hook, `{hook}` would have no device")
if "keyboard" not in hooks:
    sys.exit("luks: HOOKS has no `keyboard` hook, passphrase entry would be impossible")
print(f"luks: adding {hook} hook before filesystems in mkinitcpio.conf", file=sys.stderr)
if hook == "encrypt":
    print("luks: busybox encrypt ignores rd.luks.options, the yubikey unlock needs the systemd and sd-encrypt hooks",
          file=sys.stderr)
backup = Path("/etc/mkinitcpio.conf.arch-dotfiles-backup")
if not backup.exists():
    backup.write_text(s)
hooks.insert(hooks.index("filesystems"), hook)
p.write_text(s[:m.start(1)] + " ".join(hooks) + s[m.end(1):])
PY
fi

# sd-encrypt ships the fido2 token plugin; with no token enrolled systemd-cryptsetup falls through to the passphrase or stage.sh's keyfile
if [[ -n "$ROOT_BACKING" ]]; then
    source "$DOTFILES/configs/base/boot/common.sh"
    # a TPM2 seal first, then the yubikey, then the passphrase. tpm2-measure-pcr extends PCR 15 with the volume key once
    # unlocked, so a seal bound to PCR 15's initial zero never opens after another volume did (a swapped-in fake root)
    header=$(cryptsetup luksDump "/dev/$ROOT_BACKING")
    luks_options=tpm2-device=auto
    # tpm2-measure-pcr turns off the token plugins, and the built-in fido2-device=auto fails the unlock outright when no
    # fido2 token is enrolled ("No valid FIDO2 token data found"), passphrase never asked: only with an enrolled yubikey
    if grep -q systemd-fido2 <<<"$header"; then
        luks_options+=,fido2-device=auto
    else
        # enrolling during the stage chain would make its unattended boots wait for a touch
        echo "luks: no yubikey enrolled, once the stage chain is done: sudo systemd-cryptenroll --fido2-device=auto /dev/$ROOT_BACKING, then rerun config.sh" >&2
    fi
    kernel_cmdline_set "rd.luks.options=$luks_options,tpm2-measure-pcr=yes"
    # additive, keeps the passphrase and yubikey. never TPM-only: any signed uki would unseal it unattended, a stolen
    # machine boots to its login screen. PCR 7 tracks Secure Boot, so re-seal after enrolling or rotating SB keys
    tpm2_enroll="systemd-cryptenroll --tpm2-device=auto --tpm2-with-pin=yes --tpm2-pcrs=7+15:sha256=$PCR15_INITIAL"
    if ! grep -q systemd-tpm2 <<<"$header"; then
        echo "luks: no TPM2 seal enrolled, for a measured-boot pin unlock: sudo $tpm2_enroll /dev/$ROOT_BACKING" >&2
    elif grep -qE 'tpm2-pin:[[:space:]]+false' <<<"$header"; then
        echo "luks: a TPM2 seal without a pin unlocks any boot, replace it: sudo $tpm2_enroll --wipe-slot=tpm2 /dev/$ROOT_BACKING" >&2
    fi
    # a damaged header loses the disk; the backup goes off it, into the encrypted secrets
    echo "luks: header backup, after every keyslot change: configs/base/boot/luks/header-backup.sh (as the admin)" >&2
fi

# the encrypt hook lands in the initramfs at system-apply's boot barrier
echo "luks: crypttab configured, $added non-root LUKS volume(s) added" >&2
