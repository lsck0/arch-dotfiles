#!/usr/bin/env bash

source "$DOTFILES/configs/hardware/boot/boot-menu/common.sh"

# the kernel's CONFIG_LSM default with apparmor before bpf; active after the next reboot
if esp_supported; then
    kernel_cmdline_set lsm=landlock,lockdown,yama,integrity,apparmor,bpf
fi
systemctl enable apparmor.service

install -Dm644 modes /etc/apparmor/modes
# baseline, owned by the dotfiles. The `aa` command (link.sh) layers per-app choices into a sibling manual.conf
# in these same drop-in dirs, which this run leaves untouched, so manual decisions survive config runs.
install -Dm644 profiles.conf /etc/apparmor/flags.d/dotfiles.conf
grep -v '^#' profiles.conf | cut -d' ' -f1 | install -Dm644 /dev/stdin /etc/apparmor/include.d/dotfiles.conf
# apparmor.d assumes capitalized xdg dirs, configs/base/xdg's are lowercase
sed -n 's|^\(XDG_[A-Z]*_DIR\)="[$]HOME/\(.*\)"$|@{\1}+="\2"|p' "$DOTFILES/configs/base/xdg/user-dirs.dirs" \
    | install -Dm644 /dev/stdin /etc/apparmor.d/tunables/xdg-user-dirs.d/apparmor.d.d/dotfiles
# @{HOME}: every user's own checkout, the profile is shared by all of them
install -Dm644 local-zathura /etc/apparmor.d/local/zathura

# apparmor.d's pacman hook reruns aa-install on every transaction, this run picks up the config above
if command -v aa-install >/dev/null 2>&1; then
    aa-install --install
fi
