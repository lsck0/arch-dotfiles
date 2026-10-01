#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

# trust the mirror.lsck0.dev signing key before pacman.conf names the repo
fingerprint=$(gpg --show-keys --with-colons archrepo.asc | awk -F: '$1 == "fpr" {print $10; exit}')
sudo pacman-key --add archrepo.asc
sudo pacman-key --lsign-key "$fingerprint"
# rm first so an old link is not written through
sudo rm -f /etc/pacman.conf
# [lsck0] only while the mirror answers, an unreachable repo fails every sync
lsck0=""
if curl -fsI -m 3 http://10.200.0.210/x86_64/lsck0.db >/dev/null \
    || curl -fsI -m 10 https://mirror.lsck0.dev/x86_64/lsck0.db >/dev/null; then
    lsck0=lsck0.conf
fi
# [chaotic-aur] only once install.sh got chaotic-mirrorlist, a missing Include fails every pacman call
chaotic=0
if [[ -f /etc/pacman.d/chaotic-mirrorlist ]]; then
    chaotic=1
fi
# pacman takes a package from the first repo listing it, so [lsck0] goes above [core]
awk -v lsck0="$lsck0" -v chaotic="$chaotic" '
    BEGIN { if (lsck0 != "") while ((getline line < lsck0) > 0) repo = repo line "\n" }
    /^\[/ { skip = !chaotic && $0 == "[chaotic-aur]" }
    /^\[core\]$/ { printf "%s", repo }
    !skip { print }
' pacman.conf | sudo tee /etc/pacman.conf >/dev/null
mkdir -p "${HOME}/.config/pacman"
ln -sfn "${PWD}/makepkg.conf" "${HOME}/.config/pacman/makepkg.conf"

sudo mkdir -p /etc/pacman.d/hooks
for hook in "${PWD}"/hooks/*.hook; do
    dest="/etc/pacman.d/hooks/$(basename "${hook}")"
    if grep -q '@USER@' "${hook}"; then
        # copy with @USER@ filled in, rm as above
        sudo rm -f "${dest}"
        sed "s|@USER@|$(id -un)|" "${hook}" | sudo tee "${dest}" >/dev/null
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
