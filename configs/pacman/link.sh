#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -ex

sudo ln -sfn ${PWD}/pacman.conf /etc/pacman.conf
mkdir -p "${HOME}/.config/pacman"
ln -sfn "${PWD}/makepkg.conf" "${HOME}/.config/pacman/makepkg.conf"

sudo mkdir -p /etc/pacman.d/hooks
for hook in ${PWD}/hooks/*.hook; do
    dest="/etc/pacman.d/hooks/$(basename "${hook}")"
    if grep -q '@USER@' "${hook}"; then
        # copy with @USER@ filled in; rm first so an old link is not written through
        sudo rm -f "${dest}"
        sed "s|@USER@|$USER|" "${hook}" | sudo tee "${dest}" >/dev/null
    else
        sudo ln -sfn "${hook}" "${dest}"
    fi
done

# yay cache cleanup
mkdir -p "${HOME}/.config/systemd/user"
ln -sfn "${PWD}/yay-cache-clean.service" "${HOME}/.config/systemd/user/yay-cache-clean.service"
ln -sfn "${PWD}/yay-cache-clean.timer" "${HOME}/.config/systemd/user/yay-cache-clean.timer"
systemctl --user daemon-reload
systemctl --user enable --now yay-cache-clean.timer
