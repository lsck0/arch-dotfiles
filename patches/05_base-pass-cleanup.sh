#!/usr/bin/env bash
# base pass: drop the unbooted hardened kernel, docs and unused servers, demote the plasma/qt groups to their used members, socket-activate avahi, drop the docker prune cron and unused hyprpm repos

set -euo pipefail

DROPPED=(
    libcec linux-docs linux-hardened linux-hardened-docs linux-hardened-headers linux-lts-docs wireguard-ui-bin xrdp
)
# group installs marked every member explicit; install.sh now names the members it keeps
DEMOTED_GROUPS=(plasma qt5 qt6)
KEPT=(
    bluedevil kdeconnect kdeplasma-addons kscreen plasma-desktop plasma-integration plasma-nm plasma-pa plasma-vault
    polkit-kde-agent print-manager qt5-wayland qt6-wayland xdg-desktop-portal-kde
)

had_hardened=0
if pacman -Qq linux-hardened >/dev/null 2>&1; then
    had_hardened=1
    # before the removal, or zz-sbctl.hook fails re-signing the deleted kernel
    sudo sbctl list-files 2>/dev/null | grep -qx /boot/vmlinuz-linux-hardened && sudo sbctl remove-file /boot/vmlinuz-linux-hardened
fi

for package in "${DROPPED[@]}"; do
    pacman -Qq "$package" >/dev/null 2>&1 || continue
    # one at a time: a package another one still requires is demoted to a dependency, so -Qdt reaps it later
    sudo pacman -Rns --noconfirm "$package" || sudo pacman -D --asdeps "$package"
done

mapfile -t members < <(pacman -Qgq "${DEMOTED_GROUPS[@]}" 2>/dev/null | sort -u)
mapfile -t demoted < <(comm -23 <(printf '%s\n' "${members[@]}") <(printf '%s\n' "${KEPT[@]}" | sort))
mapfile -t kept < <(pacman -Qq "${KEPT[@]}" 2>/dev/null || true)
((${#kept[@]})) && sudo pacman -D --asexplicit "${kept[@]}" >/dev/null
((${#demoted[@]})) && sudo pacman -D --asdeps "${demoted[@]}" >/dev/null
# -tt: optional dependents (plasma-desktop suggests discover and drkonqi) do not keep a demoted member
mapfile -t orphans < <(comm -12 <(pacman -Qdttq | sort) <(printf '%s\n' "${demoted[@]}" | sort))
((${#orphans[@]})) && sudo pacman -Rns --noconfirm "${orphans[@]}"

# the esp is root-only (fmask 0077)
((had_hardened)) && sudo test -f /boot/grub/grub.cfg && sudo grub-mkconfig -o /boot/grub/grub.cfg

# only the boot want: `disable` would also drop the socket and the dbus activation alias
sudo rm -f /etc/systemd/system/multi-user.target.wants/avahi-daemon.service

sudo rm -f /etc/cron.daily/docker-prune-job

if command -v hyprpm >/dev/null 2>&1; then
    for repo in HyprGlass hyprland-plugins hy3; do
        hyprpm list 2>/dev/null | grep -qF "Repository $repo " && { yes | hyprpm remove "$repo" >/dev/null; }
    done
fi
exit 0
