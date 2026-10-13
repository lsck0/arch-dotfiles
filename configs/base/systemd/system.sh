#!/usr/bin/env bash

enable_if_present() {
    if unit_present "$1"; then systemctl enable "${@:2}" "$1"; fi
}
mask_if_present() {
    # reset-failed too: a unit that failed before being masked lingers in `systemctl --failed`
    if unit_present "$1"; then systemctl mask "$1"; systemctl reset-failed "$1" 2>/dev/null || true; fi
}

if unit_present proton.VPN.service; then systemctl disable proton.VPN.service; fi
# on demand, not at boot: the socket serves nss-mdns, the alias `enable` would add serves dbus activation
enable_if_present avahi-daemon.socket
if unit_present avahi-daemon.service; then
    link_as /usr/lib/systemd/system/avahi-daemon.service /etc/systemd/system/dbus-org.freedesktop.Avahi.service
fi
enable_if_present bluetooth.service
enable_if_present cups.socket
enable_if_present paccache.timer --now
# periodic SSD TRIM (btrfs on LUKS); weekly, shipped by util-linux
enable_if_present fstrim.timer
# thermald is intel-only, on amd it starts and exits
if grep -q GenuineIntel /proc/cpuinfo; then enable_if_present thermald.service; fi
mask_if_present NetworkManager-wait-online.service
# wine.conf is the only binfmt rule and nothing execs .exe directly; its binfmt_misc automount held sysinit.target ~1 s
mask_if_present systemd-binfmt.service
# systemd 258's NvPCR measurement (product id, user record) and its early SRK/NvPCR setup. our LUKS binds PCR 7+15 via
# tpm2-measure-pcr, never NvPCR, and cryptenroll makes the SRK on demand, so these are unused; on a TPM whose firmware
# cannot allocate the NvPCR NV indices they exit 1 ("Failed to initialize NvPCR index") and leave the system degraded
mask_if_present systemd-pcrproduct.service
mask_if_present systemd-pcrlogin@.service
mask_if_present systemd-tpm2-setup-early.service
# the initrd's systemd copies the unit from /usr/lib without the /etc mask, so it still fails there and prints
# "[FAILED] Failed to start Early TPM SRK Setup" before plymouth comes up; mask it in the initrd too, reaches the uki at
# system-apply's boot barrier
if [[ "$FORM_FACTOR" != wsl ]]; then
    source "$DOTFILES/configs/base/boot/common.sh"
    if esp_supported; then
        kernel_cmdline_set rd.systemd.mask=systemd-tpm2-setup-early.service
    fi
fi

KBD_DROPIN=/etc/systemd/system/systemd-backlight@.service.d/kbd-backlight.conf
if [[ "$FORM_FACTOR" == laptop ]]; then
    if file_update kbd-backlight.conf "$KBD_DROPIN"; then systemctl daemon-reload; fi
else
    rm -f "$KBD_DROPIN"
fi
