#!/usr/bin/env bash

enable_if_present() {
    if unit_present "$1"; then systemctl enable "${@:2}" "$1"; fi
}
mask_if_present() {
    if unit_present "$1"; then systemctl mask "$1"; fi
}

if unit_present proton.VPN.service; then systemctl disable proton.VPN.service; fi
# on demand, not at boot: the socket serves nss-mdns, the alias `enable` would add serves dbus activation
enable_if_present avahi-daemon.socket
if unit_present avahi-daemon.service; then
    ln -sfn /usr/lib/systemd/system/avahi-daemon.service /etc/systemd/system/dbus-org.freedesktop.Avahi.service
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
