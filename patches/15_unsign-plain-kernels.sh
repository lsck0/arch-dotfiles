#!/usr/bin/env bash
# unsign the plain kernels sbctl signed for grub's `linux`: grub now chainloads signed ukis, and grub.cfg on the unverified esp could chainload a signed vmlinuz with any cmdline and initrd

set -euo pipefail

command -v sbctl >/dev/null || exit 0
# configs/hardware/boot only builds ukis on the esp-at-/boot layout
[[ "$(stat -f -c %T /boot)" == msdos ]] || exit 0
for preset in /etc/mkinitcpio.d/*.preset; do
    [[ -f "$preset" ]] || continue
    pkgbase=$(basename "$preset" .preset)
    vmlinuz=/boot/vmlinuz-$pkgbase
    sbctl list-files --json 2>/dev/null | grep -qF "\"$vmlinuz\"" || continue
    # pending until this kernel boots from its uki and grub.cfg no longer boots the plain kernel
    grep -q '^default_uki=' "$preset" || exit 1
    if grep -qE "/vmlinuz-$pkgbase( |\$)" /boot/grub/grub.cfg 2>/dev/null; then
        exit 1
    fi
    # the package's copy is the unsigned original
    for pkgbase_file in /usr/lib/modules/*/pkgbase; do
        if [[ "$(<"$pkgbase_file")" == "$pkgbase" ]]; then
            install -m644 "${pkgbase_file%/*}/vmlinuz" "$vmlinuz"
        fi
    done
    # after the restore, so a failed one stays pending instead of leaving a signed kernel sbctl no longer lists
    sbctl remove-file "$vmlinuz"
done
