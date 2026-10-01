#!/usr/bin/env bash
# Stage 1, from the Arch ISO via `curl https://install-pc.lsck0.dev | sh`: wipe the disk, install a base system, arm stage.sh

set -euo pipefail

# german keyboard before any prompt; the Arch ISO defaults to us layout
loadkeys de-latin1 2>/dev/null || true

DOTFILES_URL=https://github.com/lsck0/arch-dotfiles.git
CLONE_DIR=/tmp/arch-dotfiles

# piped from curl there is no checkout yet
if [[ -z "${BASH_SOURCE[0]:-}" || ! -f "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/install.sh" ]]; then
    pacman -Sy --noconfirm --needed git
    rm -rf "$CLONE_DIR"
    git clone "$DOTFILES_URL" "$CLONE_DIR"
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
# every package group; a guest picks from these, platform files pick for luca
GROUP_UNIVERSE=(base fonts desktop socials gaming creating latex programming qemu llm pentesting)

LUKS_NAME=root
MOUNT=/mnt
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

die() { echo "bootstrap: $*" >&2; exit 1; }

confirm() {
    [[ "${BOOTSTRAP_ASSUME_YES:-0}" == 1 ]] && return 0
    local answer
    read -rp "$1 " answer </dev/tty
    [[ "$answer" == "$2" ]]
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
    # a platform file sets HOSTNAME, PKG_GROUPS, BOOT_FEATURES and WIREGUARD
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
    BOOT_FEATURES=(timeshift luks grub)
fi
[[ $EUID -eq 0 ]] || die "run as root"
[[ -d /run/archiso ]] || die "not running from the Arch ISO"
[[ -d /sys/firmware/efi ]] || die "not booted in UEFI mode"
curl -fsI -m 10 https://archlinux.org >/dev/null || die "no network"

setup_mode="$(od -An -t u1 "/sys/firmware/efi/efivars/SetupMode-$EFI_GLOBAL_GUID" 2>/dev/null | awk '{print $NF}')"
if [[ "$setup_mode" == 1 ]]; then
    (( PERSONAL )) || BOOT_FEATURES+=(sbctl)
else
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

# the password must be typed on the layout the LUKS prompt will use at boot
loadkeys "$KEYMAP"
PASSWORD="${BOOTSTRAP_PASSWORD:-}"
if [[ -z "$PASSWORD" ]]; then
    read -rsp "password (LUKS and $USERNAME): " PASSWORD </dev/tty; echo
    read -rsp "again: " again </dev/tty; echo
    [[ "$PASSWORD" == "$again" ]] || die "passwords differ"
fi
[[ -n "$PASSWORD" ]] || die "empty password"

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

printf '%s' "$PASSWORD" | cryptsetup --batch-mode luksFormat "${LUKS_FORMAT[@]}" --key-file - "$ROOT_PART"
printf '%s' "$PASSWORD" | cryptsetup open "${LUKS_OPEN[@]}" --key-file - "$ROOT_PART" "$LUKS_NAME"
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
pacstrap -K "$MOUNT" base linux linux-firmware mkinitcpio "$ucode" btrfs-progs cryptsetup grub efibootmgr \
    networkmanager sudo git zram-generator libfido2
genfstab -U "$MOUNT" >>"$MOUNT/etc/fstab"

# boot-menu (configs/boot) reads the root arguments from here, the kernel cmdline alone gets lost on regen
mkdir -p "$MOUNT/etc/kernel"
echo "rd.luks.name=$LUKS_UUID=$LUKS_NAME root=$ROOT_DEV rootflags=subvol=@ rw zswap.enabled=0 nmi_watchdog=0" >"$MOUNT/etc/kernel/cmdline"

# stage.sh's temporary unlock: a random key in its own slot, found by systemd-cryptsetup in the
# initramfs as /etc/cryptsetup-keys.d/<volume>.key; stage.sh kills the slot when the chain ends
install -dm700 "$MOUNT/etc/cryptsetup-keys.d"
head -c 64 /dev/urandom >"$MOUNT$STAGE_KEY_FILE"
chmod 600 "$MOUNT$STAGE_KEY_FILE"
# a random key needs no slow kdf, argon2id would only delay every chained boot
printf '%s' "$PASSWORD" | cryptsetup luksAddKey --key-file - --pbkdf pbkdf2 --pbkdf-force-iterations 1000 \
    "$ROOT_PART" "$MOUNT$STAGE_KEY_FILE"
install -Dm644 /dev/stdin "$MOUNT/etc/mkinitcpio.conf.d/dotfiles-stage.conf" <<<"FILES+=($STAGE_KEY_FILE)"

arch-chroot "$MOUNT" /bin/bash -euo pipefail -s -- "$HOSTNAME" "$USERNAME" "$KEYMAP" "$TIMEZONE" "$LOCALE" <<'CHROOT'
hostname=$1 user=$2 keymap=$3 timezone=$4 locale=$5

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

useradd -m -G wheel -s /bin/bash "$user"
passwd -l root
echo '%wheel ALL=(ALL:ALL) ALL' >/etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel

systemctl enable NetworkManager.service NetworkManager-wait-online.service systemd-timesyncd.service

# bootable GRUB; configs/boot/grub reinstalls it with the Secure Boot module set, sbctl signs it
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$(cat /etc/kernel/cmdline)\"|" /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
# EFI/BOOT/BOOTX64.EFI as well, for firmware that forgets its boot entries
grub-install --target=x86_64-efi --efi-directory=/boot --removable
grub-mkconfig -o /boot/grub/grub.cfg
CHROOT

printf '%s:%s\n' "$USERNAME" "$PASSWORD" | arch-chroot "$MOUNT" chpasswd

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

home="$MOUNT/home/$USERNAME"
mkdir -p "$home/projects"
cp -a "$REPO" "$home/projects/arch-dotfiles"
rm -f "$home/projects/arch-dotfiles/groups.conf" "$home/projects/arch-dotfiles/boot.conf"
# a guest has no platform file, so persist the chosen groups/boot for the unattended install
if (( ! PERSONAL )); then
    printf '%s\n' "${PKG_GROUPS[@]}" >"$home/projects/arch-dotfiles/groups.conf"
    printf '%s\n' "${BOOT_FEATURES[@]}" >"$home/projects/arch-dotfiles/boot.conf"
fi
arch-chroot "$MOUNT" chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"

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
# not oneshot: multi-user.target would wait for the whole stage, and a link.sh restarting a unit
# ordered after multi-user.target (tlp) then deadlocks
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
