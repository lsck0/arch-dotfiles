#!/usr/bin/env bash

set -e

source "$(dirname "$0")/../boot-menu/common.sh"

esp_supported || exit 0

HERE="$(cd "$(dirname "$0")" && pwd)"
MARKER="# managed by arch-dotfiles/boot/grub"

enable_initramfs_images

# native mode of the tallest connected display
gfx_width=0 gfx_height=0
for status in /sys/class/drm/card*-*/status; do
    [[ -f "$status" && "$(cat "$status")" == connected ]] || continue
    # a connector without modes is skipped like a disconnected one
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

# firmware GOP often has no 4k mode, auto then lands low and the 4k-sized font is huge; 1080p exists on nearly every GOP and gfxterm stays fast there
if (( gfx_height > 1080 )); then
    gfx_width=1920
    gfx_height=1080
fi
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

# secure boot forbids insmod, so bake every needed module into the core image
MODULES=(
    all_video boot btrfs cat chain configfile echo efifwsetup efinet ext2 fat font
    gettext gfxmenu gfxterm gfxterm_background gzio halt help iso9660 jpeg keystatus
    loadenv loopback linux ls lsefi lsefimmap lsefisystab memdisk minicmd normal
    ntfs part_gpt part_msdos password_pbkdf2 png probe reboot regexp search
    search_fs_file search_fs_uuid search_label serial sleep smbios test tpm true
    video zstd
)

height=$gfx_height
(( height > 0 )) || height=1080
font_px=$(( height / 60 ))
(( font_px > 24 )) && font_px=24
(( font_px < 12 )) && font_px=12

# grub-install writes grubx64.efi unsigned: only when grub, its modules or the theme changed, signed right after
stamp_file="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/grub-install"
stamp=$({ pacman -Q grub; echo "${MODULES[*]} $font_px"; cat /etc/hostname "$HERE"/theme/*; } | sha256sum)
if [[ "$stamp" != "$(cat "$stamp_file" 2>/dev/null)" ]] || ! sudo test -f "$ESP/EFI/GRUB/grubx64.efi"; then
    # also puts grub first in BootOrder
    sudo grub-install --target=x86_64-efi --efi-directory="$ESP" --boot-directory="$ESP" \
        --bootloader-id=GRUB --disable-shim-lock --modules="${MODULES[*]}"
    sbctl_sign "$ESP/EFI/GRUB/grubx64.efi" "$ESP/grub/x86_64-efi/core.efi" "$ESP/grub/x86_64-efi/grub.efi"
    sudo rm -rf "$ESP/grub/themes/ly"
    sudo python "$HERE/theme/render.py" "$ESP/grub/themes/ly" "$font_px" "$(cat /etc/hostname)"
    mkdir -p "${stamp_file%/*}"
    echo "$stamp" >"$stamp_file"
fi

install_boot_menu grub-snapshots

sudo install -Dm755 "$HERE/09_arch" /etc/grub.d/09_arch
sudo install -Dm644 "$HERE/grub-disable-10_linux.hook" /etc/pacman.d/hooks/grub-disable-10_linux.hook
sudo chmod -x /etc/grub.d/10_linux
# 15_uki duplicates the 09_arch kernels as plain "Arch" entries; older grub has none
sudo chmod -x /etc/grub.d/15_uki 2>/dev/null || true
sudo install -Dm755 "$HERE/41_timeshift" /etc/grub.d/41_timeshift

# limine is no longer the bootloader
sudo rm -f /etc/pacman.d/hooks/limine-deploy.hook

# grub-mkconfig and signing run once in config.sh's boot barrier
echo "grub: installed and first in BootOrder" >&2
