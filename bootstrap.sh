#!/usr/bin/env bash
# Stage 1, from the Arch ISO via the README line: wipe the disk, install a base system, arm stage.sh
#
# Integrity chain, each link checked before anything of the next one runs:
#   1. README.md pins sha256(bootstrap.sh). Its line downloads this file and runs it only if `sha256sum -c`
#      passes; sync.sh rewrites the pin on every commit. The pin is only as trustworthy as where the README
#      was read: github.com over TLS (its commit shows Verified), or better an existing checkout whose HEAD
#      passes `git verify-commit`.
#   2. This file pins SIGNING_KEY_FINGERPRINT. Run without a checkout, it clones master and execs nothing
#      from it unless HEAD carries a good signature by that primary key; sync.sh signs every Generation
#      commit with it. The signature covers the whole tree by hash, the configs/secrets gitlink included.
#   3. Packages, git and gnupg here included, are checked by pacman against the ISO's archlinux-keyring.
# Not covered: a replay of an older signed master, the `curl https://install-*.lsck0.dev | sh` short form
# (homelab and Cloudflare in the path, no pin), and a run from an existing checkout, which trusts that
# checkout as it is (test.py runs this way).
# BOOTSTRAP_INSECURE=1 deliberately skips link 2 with a warning, e.g. while master's HEAD is not signed yet.
#
# WSL (a platform with FORM_FACTOR=wsl, luca-wsl): run the README line with that platform in the fresh Arch distro's
# root shell. No disk, keyfile, bootloader or stage chain: keyring, full upgrade, the user with wheel sudo,
# /etc/wsl.conf (configs/wsl: default user, systemd, hostname) and the verified repo in ~/projects. Then, from
# Windows, `wsl --terminate archlinux`, reopen it, and run `./install.sh && ./config.sh` as the user.
#
# After stage 1: install.sh and config.sh own what they install and enable (scripts/lib/ledger.sh) and remove it
# only once dropped from the repo, after a confirmation at a terminal. LSCK0_SNAPSHOT=<YYYY-MM-DD> in the platform
# file or the env pins [lsck0] to that night's dated snapshot (configs/pacman/link.sh).

set -euo pipefail

# german keyboard before any prompt; the Arch ISO defaults to us layout
loadkeys de-latin1 2>/dev/null || true

DOTFILES_URL=https://github.com/lsck0/arch-dotfiles.git
CLONE_DIR=/tmp/arch-dotfiles
# Luca Sandrock <luca.sandrock@proton.me>: `gpg --show-keys configs/gnupg/luca-sandrock.pub.asc`, also https://github.com/lsck0.gpg
SIGNING_KEY_FINGERPRINT=E7501F533316E9AFC6AAE907122F2CB527D1EFE3
SIGNING_KEY_FILE=configs/gnupg/luca-sandrock.pub.asc

die() { echo "bootstrap: $*" >&2; exit 1; }

# clone_verify <dir>: dies unless the clone's HEAD has a good signature by SIGNING_KEY_FINGERPRINT
clone_verify() {
    local dir="$1" gnupg_home status signer verdict verified=0
    gnupg_home=$(mktemp -d)
    # the key file comes from the unverified clone, harmless: only the pinned fingerprint passes below
    GNUPGHOME="$gnupg_home" gpg --batch --quiet --import "$dir/$SIGNING_KEY_FILE" || die "cannot import $SIGNING_KEY_FILE"
    status=$(GNUPGHOME="$gnupg_home" git -C "$dir" verify-commit --raw HEAD 2>&1) && verified=1
    GNUPGHOME="$gnupg_home" gpgconf --kill all
    rm -rf "$gnupg_home"
    # gpg status line: VALIDSIG <signing key> ... <primary key>, field 12 counting the [GNUPG:] prefix
    signer=$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" {print $12}' <<<"$status")
    verdict=$(awk '$1 == "[GNUPG:]" && $2 ~ /^(GOOD|BAD|EXP|EXPKEY|REVKEY|ERR)SIG$/ {print $2}' <<<"$status" | paste -sd' ')
    if (( ! verified )) || [[ "$signer" != "$SIGNING_KEY_FINGERPRINT" ]]; then
        die "$DOTFILES_URL HEAD $(git -C "$dir" rev-parse HEAD) is not signed by $SIGNING_KEY_FINGERPRINT" \
            "(gpg: ${verdict:-NOSIG}, primary key: ${signer:-none}), refusing to run it; BOOTSTRAP_INSECURE=1 runs it unverified"
    fi
}

# pacman_init: keyring, full upgrade and what the rest needs; a fresh wsl distro ships an empty keyring and old packages
pacman_init() {
    pacman-key --init
    pacman-key --populate archlinux
    pacman -Syu --noconfirm --needed git gnupg sudo
}

# fetched alone (README line or curl | bash) there is no checkout yet
if [[ -z "${BASH_SOURCE[0]:-}" || ! -f "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/install.sh" ]]; then
    [[ "${BOOTSTRAP_INSECURE:-0}" =~ ^[01]$ ]] || die "BOOTSTRAP_INSECURE is '$BOOTSTRAP_INSECURE', expected 0 or 1"
    # the ISO's pacman-init.service already filled the keyring
    if [[ -d /run/archiso ]]; then pacman -Sy --noconfirm --needed git gnupg; else pacman_init; fi
    rm -rf "$CLONE_DIR"
    git clone "$DOTFILES_URL" "$CLONE_DIR"
    if [[ "${BOOTSTRAP_INSECURE:-0}" == 1 ]]; then
        echo "bootstrap: WARNING: BOOTSTRAP_INSECURE=1, running $(git -C "$CLONE_DIR" rev-parse HEAD) as root WITHOUT checking its signature" >&2
    else
        clone_verify "$CLONE_DIR"
    fi
    exec bash "$CLONE_DIR/bootstrap.sh" "$@" </dev/tty
fi

REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PLATFORM="${1:-}"

# defaults, overridden per platform
KEYMAP=de-latin1
TIMEZONE=Europe/Berlin
LOCALE=en_US.UTF-8
ESP_SIZE_MIB=1024
HOSTNAME=""

LUKS_NAME=root
MOUNT=/mnt
# the installed system's root: the mounted disk from the ISO, the running distro under wsl
TARGET_ROOT=$MOUNT
BTRFS_OPTS="noatime,compress=zstd"
SUBVOLS=("@:/" "@home:/home" "@log:/var/log" "@pkg:/var/cache/pacman/pkg" "@.snapshots:/.snapshots")
# the README's former manual reencrypt, done at format time instead
LUKS_FORMAT=(--type luks2 --cipher aes-xts-plain64 --key-size 256 --sector-size 4096 --pbkdf argon2id)
LUKS_OPEN=(--allow-discards --perf-no_read_workqueue --perf-no_write_workqueue --persistent)
STAGE_STATE_DIR=/var/lib/dotfiles-stage
STAGE_KEY_FILE=/etc/cryptsetup-keys.d/root.key
EFI_GLOBAL_GUID=8be4df61-93ca-11d2-aa0d-00e098032b8c
REBOOT_DELAY_S=10
SYNC_WAIT_S=120

confirm() {
    [[ "${BOOTSTRAP_ASSUME_YES:-0}" == 1 ]] && return 0
    local answer
    read -rp "$1 " answer </dev/tty
    [[ "$answer" == "$2" ]]
}

# read_password <prompt>: hidden, typed twice unless empty, so the caller can apply its default
read_password() {
    local first second
    read -rsp "$1: " first </dev/tty; echo >&2
    if [[ -n "$first" ]]; then
        read -rsp "again: " second </dev/tty; echo >&2
        [[ "$first" == "$second" ]] || die "passwords differ"
    fi
    printf '%s' "$first"
}

# in_target <cmd...>: run in the installed system, through arch-chroot from the ISO, directly under wsl
in_target() {
    if [[ -n "$TARGET_ROOT" ]]; then arch-chroot "$TARGET_ROOT" "$@"; else "$@"; fi
}

# user_setup: the login user with its password and wheel sudo, root locked unless given one, the verified repo at home
user_setup() {
    local repo_copy="$TARGET_ROOT/home/$USERNAME/projects/arch-dotfiles"
    in_target id -u "$USERNAME" >/dev/null 2>&1 || in_target useradd -m -G wheel -s /bin/bash "$USERNAME"
    printf '%s:%s\n' "$USERNAME" "$USER_PASSWORD" | in_target chpasswd
    in_target passwd -l root >/dev/null
    # root keeps that lock unless it was given its own password
    [[ -z "$ROOT_PASSWORD" ]] || printf 'root:%s\n' "$ROOT_PASSWORD" | in_target chpasswd
    # sudo skips a drop-in named with a dot, so this one is checked before it can lock anyone out
    install -Dm440 /dev/stdin "$TARGET_ROOT/etc/sudoers.d/10-wheel.new" <<<'%wheel ALL=(ALL:ALL) ALL'
    in_target visudo -cqf /etc/sudoers.d/10-wheel.new || die "the wheel sudoers drop-in does not parse"
    mv -f "$TARGET_ROOT/etc/sudoers.d/10-wheel.new" "$TARGET_ROOT/etc/sudoers.d/10-wheel"
    # a rerun under wsl keeps the checkout and whatever work is in it
    if [[ ! -e "$repo_copy" ]]; then
        mkdir -p "${repo_copy%/*}"
        cp -a "$REPO" "$repo_copy"
        # a guest has no platform file, so the choice becomes one; FORM_FACTOR stays a probe
        if (( ! PERSONAL )); then
            printf 'HOSTNAME=%s\nPKG_GROUPS=(%s)\n' "$HOSTNAME" "${PKG_GROUPS[*]}" >"$repo_copy/platforms/local.sh"
        fi
    fi
    in_target chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"
}

# --- preflight ----------------------------------------------------------------

# the username decides personal (luca) vs guest; a guest gets no secrets, identity, or homelab
USERNAME="${BOOTSTRAP_USERNAME:-}"
if [[ -z "$USERNAME" ]]; then
    if [[ "${BOOTSTRAP_ASSUME_YES:-0}" == 1 ]]; then
        USERNAME=luca
    else
        read -rp "username [luca]: " USERNAME </dev/tty; USERNAME="${USERNAME:-luca}"
    fi
fi
PERSONAL=0; [[ "$USERNAME" == luca ]] && PERSONAL=1

if (( PERSONAL )); then
    # a platform file sets HOSTNAME, PKG_GROUPS and WIREGUARD
    mapfile -t platforms < <(cd "$REPO/platforms" && for f in *.sh; do echo "${f%.sh}"; done)
    if [[ -z "$PLATFORM" ]]; then
        echo "platforms: ${platforms[*]}"
        read -rp "platform: " PLATFORM </dev/tty
    fi
    PLATFORM_FILE="$REPO/platforms/$PLATFORM.sh"
    [[ -f "$PLATFORM_FILE" ]] || die "unknown platform '$PLATFORM', one of: ${platforms[*]}"
    # shellcheck source=/dev/null
    source "$PLATFORM_FILE"
    [[ -n "$HOSTNAME" ]] || die "$PLATFORM_FILE sets no HOSTNAME"
else
    # guest: no platform file, so take the hostname and groups from env/prompt (env for an unattended run)
    HOSTNAME="${BOOTSTRAP_HOSTNAME:-}"
    if [[ -z "$HOSTNAME" ]]; then
        if [[ "${BOOTSTRAP_ASSUME_YES:-0}" == 1 ]]; then HOSTNAME="$USERNAME-pc"
        else read -rp "hostname: " HOSTNAME </dev/tty; fi
    fi
    [[ -n "$HOSTNAME" ]] || die "empty hostname"
    # every group install.sh tags; a guest picks from these, platform files pick for luca
    source "$REPO/scripts/lib/platform.sh"
    mapfile -t GROUP_UNIVERSE < <(platform_groups_all "$REPO")
    if [[ -n "${BOOTSTRAP_GROUPS:-}" ]]; then
        read -ra PKG_GROUPS <<<"$BOOTSTRAP_GROUPS"
    elif [[ "${BOOTSTRAP_ASSUME_YES:-0}" == 1 ]]; then
        PKG_GROUPS=("${GROUP_UNIVERSE[@]}")
    else
        echo "package groups:" >&2
        for i in "${!GROUP_UNIVERSE[@]}"; do printf '  %d  %s\n' "$((i + 1))" "${GROUP_UNIVERSE[i]}" >&2; done
        read -rp "numbers to EXCLUDE (space-separated), enter for all: " -a excludes </dev/tty
        PKG_GROUPS=()
        for i in "${!GROUP_UNIVERSE[@]}"; do
            skip=0
            for n in "${excludes[@]}"; do [[ "$n" == "$((i + 1))" ]] && skip=1; done
            (( skip )) || PKG_GROUPS+=("${GROUP_UNIVERSE[i]}")
        done
    fi
fi
[[ $EUID -eq 0 ]] || die "run as root"

# --- wsl ----------------------------------------------------------------------

# the distro's own root shell instead of the ISO: windows owns disk, kernel and boot
if [[ "${FORM_FACTOR:-}" == wsl ]]; then
    [[ "$(systemd-detect-virt 2>/dev/null)" == wsl ]] || die "$PLATFORM is a wsl platform, run it in the distro's root shell"
    pacman_init
    USER_PASSWORD="${BOOTSTRAP_USER_PASSWORD:-}"
    [[ -n "$USER_PASSWORD" ]] || USER_PASSWORD=$(read_password "$USERNAME password")
    [[ -n "$USER_PASSWORD" ]] || die "empty password"
    ROOT_PASSWORD="${BOOTSTRAP_ROOT_PASSWORD:-}"
    TARGET_ROOT=""
    user_setup
    echo "$HOSTNAME" >/etc/hostname
    sed -e "s|@USER@|$USERNAME|" -e "s|@HOSTNAME@|$HOSTNAME|" "$REPO/configs/wsl/wsl.conf" | install -Dm644 /dev/stdin /etc/wsl.conf
    echo "bootstrap: done. from windows: wsl --terminate archlinux, reopen it (now $USERNAME with systemd), then:"
    echo "  cd ~/projects/arch-dotfiles && ./install.sh && ./config.sh"
    exit 0
fi

[[ -d /run/archiso ]] || die "not running from the Arch ISO"
[[ -d /sys/firmware/efi ]] || die "not booted in UEFI mode"
curl -fsI -m 10 https://archlinux.org >/dev/null || die "no network"

setup_mode="$(od -An -t u1 "/sys/firmware/efi/efivars/SetupMode-$EFI_GLOBAL_GUID" 2>/dev/null | awk '{print $NF}')"
if [[ "$setup_mode" != 1 ]]; then
    echo "bootstrap: firmware is not in Secure Boot Setup Mode, so install.sh cannot enroll keys" >&2
    confirm "continue without Secure Boot? [y/N]" y || die "enable Setup Mode in the firmware, then rerun"
fi

# --- disk ---------------------------------------------------------------------

DISK="${BOOTSTRAP_DISK:-}"
if [[ -z "$DISK" ]]; then
    mapfile -t disks < <(lsblk -dnpo NAME,TYPE,RM | awk '$2 == "disk" && $3 == 0 {print $1}' | grep -v -e zram -e loop)
    (( ${#disks[@]} )) || die "no disk found (set BOOTSTRAP_DISK)"
    if (( ${#disks[@]} == 1 )); then
        DISK="${disks[0]}"
    else
        lsblk -dpo NAME,SIZE,MODEL "${disks[@]}" >&2
        PS3="disk to erase: "
        select d in "${disks[@]}"; do [[ -n "$d" ]] && { DISK="$d"; break; }; done </dev/tty
    fi
fi
[[ -b "$DISK" ]] || die "$DISK is not a block device"

lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL "$DISK"
confirm "ERASE ALL DATA on $DISK? type the device path to confirm:" "$DISK" || die "aborted"

# the passwords must be typed on the layout the LUKS prompt and the console login will use
loadkeys "$KEYMAP"
# unattended: BOOTSTRAP_PASSWORD is the LUKS one and nothing is asked; the user's defaults to it, root stays locked
LUKS_PASSWORD="${BOOTSTRAP_PASSWORD:-}"
USER_PASSWORD="${BOOTSTRAP_USER_PASSWORD:-}"
ROOT_PASSWORD="${BOOTSTRAP_ROOT_PASSWORD:-}"
if [[ -z "$LUKS_PASSWORD" ]]; then
    LUKS_PASSWORD=$(read_password "LUKS password")
    [[ -n "$LUKS_PASSWORD" ]] || die "empty LUKS password"
    [[ -n "$USER_PASSWORD" ]] || USER_PASSWORD=$(read_password "$USERNAME password [LUKS password]")
    [[ -n "$ROOT_PASSWORD" ]] || ROOT_PASSWORD=$(read_password "root password [locked]")
fi
USER_PASSWORD="${USER_PASSWORD:-$LUKS_PASSWORD}"

# --- partition, encrypt, format -----------------------------------------------

umount -R "$MOUNT" 2>/dev/null || true
cryptsetup close "$LUKS_NAME" 2>/dev/null || true
wipefs -af "$DISK"
sgdisk --zap-all "$DISK"
sgdisk -n "1:0:+${ESP_SIZE_MIB}M" -t 1:ef00 -c 1:ESP "$DISK"
# LUKS with 4096-byte sectors needs the partition size in whole 4 KiB, the free space rarely is
sectors_per_4k=$((4096 / $(blockdev --getss "$DISK")))
root_start=$(sgdisk -F "$DISK")
root_last=$(sgdisk -E "$DISK")
root_end=$((root_start + (root_last - root_start + 1) / sectors_per_4k * sectors_per_4k - 1))
sgdisk -n "2:$root_start:$root_end" -t 2:8309 -c 2:cryptroot "$DISK"
partprobe "$DISK"
udevadm settle
mapfile -t parts < <(lsblk -lnpo NAME,TYPE "$DISK" | awk '$2 == "part" {print $1}')
(( ${#parts[@]} == 2 )) || die "expected 2 partitions on $DISK after partitioning, got ${#parts[@]}"
ESP_PART="${parts[0]}"
ROOT_PART="${parts[1]}"

printf '%s' "$LUKS_PASSWORD" | cryptsetup --batch-mode luksFormat "${LUKS_FORMAT[@]}" --key-file - "$ROOT_PART"
printf '%s' "$LUKS_PASSWORD" | cryptsetup open "${LUKS_OPEN[@]}" --key-file - "$ROOT_PART" "$LUKS_NAME"
LUKS_UUID="$(cryptsetup luksUUID "$ROOT_PART")"
ROOT_DEV="/dev/mapper/$LUKS_NAME"

mkfs.fat -F 32 -n ESP "$ESP_PART"
mkfs.btrfs -f -L arch "$ROOT_DEV"

mount "$ROOT_DEV" "$MOUNT"
for entry in "${SUBVOLS[@]}"; do btrfs subvolume create "$MOUNT/${entry%%:*}"; done
umount "$MOUNT"
for entry in "${SUBVOLS[@]}"; do
    mountpoint="$MOUNT${entry#*:}"
    mkdir -p "$mountpoint"
    mount -o "$BTRFS_OPTS,subvol=${entry%%:*}" "$ROOT_DEV" "$mountpoint"
done
mkdir -p "$MOUNT/boot"
mount -o umask=0077 "$ESP_PART" "$MOUNT/boot"

# --- base system --------------------------------------------------------------

# pacstrap verifies signatures: needs a synced clock and the iso's keyring refresh to have finished
for ((i = 0; i < SYNC_WAIT_S; i++)); do
    [[ "$(timedatectl show -p NTPSynchronized --value)" == yes ]] \
        && ! systemctl is-active --quiet archlinux-keyring-wkd-sync.service && break
    sleep 1
done

ucode=amd-ucode
grep -q GenuineIntel /proc/cpuinfo && ucode=intel-ucode

# homelab mirror first so pacstrap pulls base at lan speed; pacman falls through to the iso's public mirrors when away
sed -i '1i Server = http://10.100.0.109:8090/archlinux/$repo/os/$arch' /etc/pacman.d/mirrorlist

pacstrap -K "$MOUNT" base linux linux-firmware mkinitcpio "$ucode" btrfs-progs cryptsetup grub efibootmgr \
    networkmanager sudo git zram-generator libfido2
genfstab -U "$MOUNT" >>"$MOUNT/etc/fstab"

# boot-menu (configs/boot) reads the root arguments from here, the kernel cmdline alone gets lost on regen
mkdir -p "$MOUNT/etc/kernel"
echo "rd.luks.name=$LUKS_UUID=$LUKS_NAME root=$ROOT_DEV rootflags=subvol=@ rw zswap.enabled=0 nmi_watchdog=0" >"$MOUNT/etc/kernel/cmdline"

# stage.sh's temporary unlock: a random key in its own slot, found by systemd-cryptsetup in the initramfs as /etc/cryptsetup-keys.d/<volume>.key; stage.sh kills the slot when the chain ends
install -dm700 "$MOUNT/etc/cryptsetup-keys.d"
head -c 64 /dev/urandom >"$MOUNT$STAGE_KEY_FILE"
chmod 600 "$MOUNT$STAGE_KEY_FILE"
# a random key needs no slow kdf, argon2id would only delay every chained boot
printf '%s' "$LUKS_PASSWORD" | cryptsetup luksAddKey --key-file - --pbkdf pbkdf2 --pbkdf-force-iterations 1000 \
    "$ROOT_PART" "$MOUNT$STAGE_KEY_FILE"
install -Dm644 /dev/stdin "$MOUNT/etc/mkinitcpio.conf.d/dotfiles-stage.conf" <<<"FILES+=($STAGE_KEY_FILE)"

arch-chroot "$MOUNT" /bin/bash -euo pipefail -s -- "$HOSTNAME" "$KEYMAP" "$TIMEZONE" "$LOCALE" <<'CHROOT'
hostname=$1 keymap=$2 timezone=$3 locale=$4

ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
hwclock --systohc
sed -i "s/^#\($locale \)/\1/" /etc/locale.gen
locale-gen
echo "LANG=$locale" >/etc/locale.conf
echo "KEYMAP=$keymap" >/etc/vconsole.conf
echo "$hostname" >/etc/hostname
printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 %s\n' "$hostname" >/etc/hosts

# systemd initramfs: sd-vconsole so the LUKS prompt uses the right keymap
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

systemctl enable NetworkManager.service NetworkManager-wait-online.service systemd-timesyncd.service

# bootable GRUB; configs/boot/grub reinstalls it with the Secure Boot module set, sbctl signs it
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$(cat /etc/kernel/cmdline)\"|" /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
# EFI/BOOT/BOOTX64.EFI as well, for firmware that forgets its boot entries
grub-install --target=x86_64-efi --efi-directory=/boot --removable
grub-mkconfig -o /boot/grub/grub.cfg
CHROOT

# zram swap from the first boot, install.sh compiles for hours before config.sh would link it
install -Dm644 "$REPO/configs/zram/zram-generator.conf" "$MOUNT/etc/systemd/zram-generator.conf"

# --- network --------------------------------------------------------------------

# the wifi the ISO connected with (iwctl), so the chained boots come up online
for psk in /var/lib/iwd/*.psk; do
    [[ -f "$psk" ]] || continue
    ssid=$(basename "$psk" .psk)
    # iwd hex-encodes ssids that are not plain ascii as =<hex>
    if [[ "$ssid" == =* ]]; then
        ssid=$(printf '%b' "$(sed 's/../\\x&/g' <<<"${ssid#=}")")
    fi
    passphrase=$(sed -n 's/^Passphrase=//p' "$psk")
    [[ -n "$passphrase" ]] || continue
    install -Dm600 /dev/stdin "$MOUNT/etc/NetworkManager/system-connections/$ssid.nmconnection" <<NM
[connection]
id=$ssid
type=wifi

[wifi]
ssid=$ssid

[wifi-security]
key-mgmt=wpa-psk
psk=$passphrase

[ipv4]
method=auto

[ipv6]
method=auto
NM
done

# --- dotfiles and the stage chain ---------------------------------------------

# luca: pull and unlock the secrets here (the one tap window), so the chained config boot needs no touch
if (( PERSONAL )); then
    pacman -Sy --noconfirm --needed age age-plugin-yubikey git-crypt pcsclite ccid libfido2 \
        || echo "bootstrap: secrets toolchain install failed, config will unlock instead" >&2
    systemctl start pcscd.socket 2>/dev/null || true
    ( cd "$REPO" && ./scripts/yubikey.sh unlock ) || echo "bootstrap: secrets unlock skipped" >&2
fi

user_setup

install -Dm644 /dev/stdin "$MOUNT$STAGE_STATE_DIR/next" <<<"install"
install -Dm644 /dev/stdin "$MOUNT$STAGE_STATE_DIR/luks-device" <<<"/dev/disk/by-uuid/$LUKS_UUID"
# verifypw=any: with %wheel still asking, `sudo -v` would want a password despite the NOPASSWD rule
printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\nDefaults:%s verifypw=any\n' "$USERNAME" "$USERNAME" \
    | install -Dm440 /dev/stdin "$MOUNT/etc/sudoers.d/zz-dotfiles-stage"
# PAMName gives the stages a logind session, so user units and dbus work like after a login
install -Dm644 /dev/stdin "$MOUNT/etc/systemd/system/dotfiles-stage.service" <<UNIT
[Unit]
Description=arch-dotfiles install chain (stage.sh)
Wants=network-online.target
After=network-online.target
ConditionPathExists=$STAGE_STATE_DIR/next

[Service]
# not oneshot: multi-user.target would wait for the whole stage, and a link.sh restarting a unit ordered after multi-user.target (tlp) then deadlocks
Type=exec
User=$USERNAME
PAMName=login
WorkingDirectory=/home/$USERNAME/projects/arch-dotfiles
ExecStart=/home/$USERNAME/projects/arch-dotfiles/stage.sh
# a tty, not journal+console, so install.sh re-execs under script and pacman draws its bars; install.log keeps the output
StandardOutput=tty
TimeoutStartSec=infinity

[Install]
WantedBy=multi-user.target
UNIT
arch-chroot "$MOUNT" systemctl enable dotfiles-stage.service

umount -R "$MOUNT"
cryptsetup close "$LUKS_NAME"
echo "bootstrap: done, rebooting in $REBOOT_DELAY_S s; remove the ISO. the next boots run install.sh and config.sh by themselves"
sleep "$REBOOT_DELAY_S"
reboot
