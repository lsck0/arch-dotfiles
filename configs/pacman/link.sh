#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -ex

# trust the mirror.lsck0.dev signing key before pacman.conf names the repo
fingerprint=$(gpg --show-keys --with-colons archrepo.asc | awk -F: '$1 == "fpr" {print $10; exit}')
sudo pacman-key --add archrepo.asc
sudo pacman-key --lsign-key "$fingerprint"
# rm first so an old link is not written through
sudo rm -f /etc/pacman.conf
# [lsck0] only while the mirror answers, an unreachable repo fails every sync
if curl -fsI -m 10 https://mirror.lsck0.dev/x86_64/lsck0.db >/dev/null; then
    cat pacman.conf lsck0.conf | sudo tee /etc/pacman.conf >/dev/null
else
    sudo install -m644 pacman.conf /etc/pacman.conf
fi
mkdir -p "${HOME}/.config/pacman"
ln -sfn "${PWD}/makepkg.conf" "${HOME}/.config/pacman/makepkg.conf"

sudo mkdir -p /etc/pacman.d/hooks
for hook in "${PWD}"/hooks/*.hook; do
    dest="/etc/pacman.d/hooks/$(basename "${hook}")"
    if grep -q '@USER@' "${hook}"; then
        # copy with @USER@ filled in, rm as above
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
