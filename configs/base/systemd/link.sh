#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

unit_file_present() {
    local unit="$1" lookup="$1"
    case "$unit" in
        *@*.*) lookup="${unit%%@*}@.${unit##*.}" ;;
    esac
    systemctl list-unit-files --no-legend "$lookup" 2>/dev/null | grep -q .
}

enable_if_present() {
    if unit_file_present "$1"; then
        sudo systemctl enable "${@:2}" "$1"
    fi
}

disable_if_present() {
    if unit_file_present "$1"; then
        sudo systemctl disable "$1"
    fi
}

mask_if_present() {
    if unit_file_present "$1"; then
        sudo systemctl mask "$1"
    fi
}

mask_user_if_present() {
    if systemctl --user list-unit-files --no-legend "$1" 2>/dev/null | grep -q .; then
        systemctl --user mask "$1"
    fi
}

disable_if_present proton.VPN.service
# on demand, not at boot: the socket serves nss-mdns, the alias `enable` would add serves dbus activation
enable_if_present avahi-daemon.socket
unit_file_present avahi-daemon.service \
    && sudo ln -sfn /usr/lib/systemd/system/avahi-daemon.service /etc/systemd/system/dbus-org.freedesktop.Avahi.service
enable_if_present bluetooth.service
enable_if_present cups.socket
enable_if_present paccache.timer --now
# thermald is intel-only, on amd it starts and exits
grep -q GenuineIntel /proc/cpuinfo && enable_if_present thermald.service
mask_if_present NetworkManager-wait-online.service
# wine.conf is the only binfmt rule and nothing execs .exe directly; its binfmt_misc automount held sysinit.target ~1 s
mask_if_present systemd-binfmt.service

# ly's pam stack already starts and unlocks the keyring
mask_user_if_present gnome-keyring-daemon.service
mask_user_if_present gnome-keyring-daemon.socket

for unit in pipewire-pulse.service pipewire-pulse.socket ssh-agent.service; do
    if systemctl --user list-unit-files --no-legend "$unit" 2>/dev/null | grep -q .; then
        systemctl --user enable "$unit"
    fi
done
