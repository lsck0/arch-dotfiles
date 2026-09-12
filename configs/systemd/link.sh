#!/usr/bin/env bash

set -ex

enable_if_present() {
    if systemctl list-unit-files --no-legend "$1" 2>/dev/null | grep -q .; then
        sudo systemctl enable "${@:2}" "$1"
    fi
}

disable_if_present() {
    if systemctl list-unit-files --no-legend "$1" 2>/dev/null | grep -q .; then
        sudo systemctl disable "$1"
    fi
}

mask_if_present() {
    if systemctl list-unit-files --no-legend "$1" 2>/dev/null | grep -q .; then
        sudo systemctl mask "$1"
    fi
}

sudo systemctl disable getty@tty2.service

disable_if_present proton.VPN.service
enable_if_present avahi-daemon.service
enable_if_present bluetooth.service
enable_if_present cronie.service
enable_if_present cups.socket
enable_if_present libvirtd.service
enable_if_present ly@tty2.service
enable_if_present nix-daemon.socket
enable_if_present open-fprintd-resume.service
enable_if_present open-fprintd-suspend.service
enable_if_present ossec-server.target
enable_if_present paccache.timer --now
enable_if_present thermald.service
mask_if_present NetworkManager-wait-online.service

for unit in pipewire-pulse.service pipewire-pulse.socket ssh-agent.service; do
    if systemctl --user list-unit-files --no-legend "$unit" 2>/dev/null | grep -q .; then
        systemctl --user enable "$unit"
done
