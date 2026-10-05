#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v apparmor_parser >/dev/null 2>&1; then
    exit 0
fi

set -e

source ../boot/boot-menu/common.sh

# the kernel's CONFIG_LSM default with apparmor before bpf; active after the next reboot
if esp_supported; then
    kernel_cmdline_set lsm=landlock,lockdown,yama,integrity,apparmor,bpf
fi
sudo systemctl enable apparmor.service

sudo install -Dm644 modes /etc/apparmor/modes
sudo install -Dm644 profiles.conf /etc/apparmor/flags.d/dotfiles.conf
grep -v '^#' profiles.conf | cut -d' ' -f1 | sudo install -Dm644 /dev/stdin /etc/apparmor/include.d/dotfiles.conf
# apparmor.d assumes capitalized xdg dirs, configs/xdg's are lowercase
sed -n 's|^\(XDG_[A-Z]*_DIR\)="[$]HOME/\(.*\)"$|@{\1}+="\2"|p' ../xdg/user-dirs.dirs \
    | sudo install -Dm644 /dev/stdin /etc/apparmor.d/tunables/xdg-user-dirs.d/apparmor.d.d/dotfiles
sed "s|@REPO@|$(cd ../.. && pwd)|" local-zathura | sudo install -Dm644 /dev/stdin /etc/apparmor.d/local/zathura

# apparmor.d's pacman hook reruns aa-install on every transaction, this run picks up the config above
if command -v aa-install >/dev/null 2>&1; then
    sudo aa-install --install
fi
