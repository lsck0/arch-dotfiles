#!/usr/bin/env bash
# after a timeshift restore of @ the esp (not in @) still holds the newer kernels, whose modules the restored
# /usr/lib/modules lacks: put each installed kernel back on the esp and rebuild its uki, as the kernel package's own
# hook does (sbctl's mkinitcpio post hook signs it), then reboot once when the running kernel was one of them
set -euo pipefail

resynced=0
for pkgbase_file in /usr/lib/modules/*/pkgbase; do
    dir=${pkgbase_file%/*}
    kver=${dir##*/}
    pkgbase=$(<"$pkgbase_file")
    [[ -f "$dir/vmlinuz" ]] || continue
    # by the version in the image header, so a signed copy still matches
    [[ "$(file -bL "/boot/vmlinuz-$pkgbase" 2>/dev/null)" == *", version $kver "* ]] && continue
    echo "kernel-resync: /boot/vmlinuz-$pkgbase is not $kver, restoring it from the installed $pkgbase" >&2
    install -Dm644 "$dir/vmlinuz" "/boot/vmlinuz-$pkgbase"
    mkinitcpio -p "$pkgbase"
    resynced=1
done

# the next boot finds the kernel in step, so this reboots at most once; from the iso (ROLLBACK.md) the chroot just ends
if ((resynced)) && [[ ! -d "/usr/lib/modules/$(uname -r)" ]] && ! systemd-detect-virt -q --chroot; then
    echo "kernel-resync: running $(uname -r) without its modules, rebooting into the restored kernel" >&2
    systemctl reboot
fi
