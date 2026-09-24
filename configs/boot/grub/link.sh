#!/usr/bin/env bash

set -ex

source "$(dirname "$0")/../boot-menu/common.sh"

if ! bootloader_selected grub; then
    exit 0
fi
if ! command -v grub-install >/dev/null 2>&1; then
    echo "grub: selected in boot.conf but not installed" >&2
    exit 1
fi
esp_supported || exit 0

HERE="$(cd "$(dirname "$0")" && pwd)"
MARKER="# managed by arch-dotfiles/boot/grub"

enable_initramfs_images

# Detect the tallest connected display's native mode once
gfx_width=0 gfx_height=0
for status in /sys/class/drm/card*-*/status; do
    [[ -f "$status" && "$(cat "$status")" == connected ]] || continue
    mode="$(head -1 "$(dirname "$status")/modes" 2>/dev/null || true)"
    [[ "$mode" == *x* ]] || continue
    w="${mode%%x*}"
    h="${mode#*x}"
    h="${h%%[^0-9]*}"
    if [[ -n "$h" ]] && (( h > gfx_height )); then
        gfx_width=$w
        gfx_height=$h
    fi
done

if (( gfx_width > 0 && gfx_height > 0 )); then
    GFXMODE="${gfx_width}x${gfx_height},auto"
else
    GFXMODE="auto"
fi

if [[ -f /etc/default/grub ]] && ! grep -qF "$MARKER" /etc/default/grub; then
    sudo install -m644 /etc/default/grub /etc/default/grub.arch-dotfiles-backup
fi
sed "s/@GFXMODE@/$GFXMODE/" "$HERE/grub.default" | sudo tee /etc/default/grub >/dev/null
sudo chmod 644 /etc/default/grub

# Under Secure Boot GRUB refuses to insmod anything, so every module the config, the snapshot menu and the theme need is baked into the (signed) core image.
MODULES=(
    all_video boot btrfs cat chain configfile echo efifwsetup efinet ext2 fat font
    gettext gfxmenu gfxterm gfxterm_background gzio halt help iso9660 jpeg keystatus
    loadenv loopback linux ls lsefi lsefimmap lsefisystab memdisk minicmd normal
    ntfs part_gpt part_msdos password_pbkdf2 png probe reboot regexp search
    search_fs_file search_fs_uuid search_label serial sleep smbios test tpm true
    video zstd
)
# grub-install also puts its EFI entry first in BootOrder.
sudo grub-install --target=x86_64-efi --efi-directory="$ESP" --boot-directory="$ESP" \
    --bootloader-id=GRUB --disable-shim-lock --modules="${MODULES[*]}"

height=$gfx_height
(( height > 0 )) || height=1080
# height/60 alone is a pure 1:1 pixel scale: 18px at 1080p, but 36px at 2160p, which fills the screen with a menu you can read from the sofa.
font_px=$(( height / 60 ))
(( font_px > 24 )) && font_px=24
(( font_px < 12 )) && font_px=12
sudo rm -rf "$ESP/grub/themes/ly"
sudo python "$HERE/theme/render.py" "$ESP/grub/themes/ly" "$font_px" "$(cat /etc/hostname 2>/dev/null || hostname)"

install_boot_menu grub-snapshots

# Kernel entries named per package instead of 10_linux's "Arch" for every kernel.
sudo install -Dm755 "$HERE/09_arch" /etc/grub.d/09_arch
sudo install -Dm644 "$HERE/grub-disable-10_linux.hook" /etc/pacman.d/hooks/grub-disable-10_linux.hook
sudo chmod -x /etc/grub.d/10_linux
# 15_uki emits GRUB's `uki` command, which auto-discovers every UKI in EFI/Linux and titles all of them "$GRUB_DISTRIBUTOR" — three more entries called plain "Arch" for the same three kernels 09_arch already lists by name.
sudo chmod -x /etc/grub.d/15_uki 2>/dev/null || true
sudo install -Dm755 "$HERE/41_timeshift" /etc/grub.d/41_timeshift

# limine is not the bootloader any more; stop deploying it on upgrades.
sudo rm -f /etc/pacman.d/hooks/limine-deploy.hook

sudo grub-mkconfig -o "$ESP/grub/grub.cfg"

sbctl_sign "$ESP/EFI/GRUB/grubx64.efi" "$ESP"/vmlinuz-*

echo "grub: installed and first in BootOrder" >&2
