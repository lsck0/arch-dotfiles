#!/usr/bin/env bash

set -ex

# avahi, libvirt, and the fingerprint driver stack (open-fprintd) are not in
# install.sh's own PACKAGES/CARGO_PKGS lists — they get installed by hand, if
# at all. Without this guard, `set -e` means a machine missing any one of
# them aborts this script right there and skips every enable after it too
# (bluetooth, cronie, cups, ly, nix-daemon, ossec, thermald, paccache,
# the NetworkManager-wait-online mask), even though install.sh does
# guarantee those. Guard only the not-guaranteed ones.
enable_if_present() {
    if systemctl list-unit-files --no-legend "$1" 2>/dev/null | grep -q .; then
        sudo systemctl enable "$1"
    else
        echo "skip: $1 not installed" >&2
    fi
}

sudo systemctl disable getty@tty2.service
enable_if_present avahi-daemon.service
sudo systemctl enable bluetooth.service
sudo systemctl enable cronie.service
# socket-activated: cupsd only starts on first print/admin request, not at boot
sudo systemctl enable cups.socket
enable_if_present libvirtd.service
sudo systemctl enable ly@tty2.service
# socket-activated: nix-daemon only starts on first use, not at boot
sudo systemctl enable nix-daemon.socket
enable_if_present open-fprintd-resume.service
enable_if_present open-fprintd-suspend.service
sudo systemctl enable ossec-server.target
sudo systemctl enable thermald.service
# periodic `paccache -r`, keeps CacheDir from growing unbounded (needs pacman-contrib)
sudo systemctl enable --now paccache.timer

# These used to be enabled by configs/systemd/manual_link.sh. Keep them in
# the normal idempotent linker: enabling an already-running unit is harmless
# and does not require a reboot or user-session restart.
systemctl --user enable pipewire-pulse.service pipewire-pulse.socket ssh-agent.service

# don't let network-online.target hold up graphical.target waiting on DHCP/Wi-Fi
sudo systemctl mask NetworkManager-wait-online.service

# proton-vpn-daemon ships its own D-Bus activation file
# (/usr/share/dbus-1/system-services/me.proton.vpn.split_tunneling.service,
# SystemdService=proton.VPN.service) but is *also* WantedBy=multi-user.target
# by default, which starts it unconditionally at boot even if ProtonVPN is
# never used that session. Disabling the boot-time enable doesn't break
# anything — verified live: `busctl introspect me.proton.vpn.split_tunneling /`
# against a stopped+disabled unit made systemd start it on demand via the
# dbus activation file, journal confirmed "Started Proton VPN Daemon."
# `protonvpn status` doesn't even need the daemon up at all (works while
# it's fully down); `protonvpn connect` needs the split-tunneling dbus
# call, which is exactly what triggers the lazy start.
sudo systemctl disable proton.VPN.service

# on-demand, not at boot: `systemctl start ollama` / `waydroid container start` when needed
# sudo systemctl enable ollama.service
# sudo systemctl enable waydroid-container.service
