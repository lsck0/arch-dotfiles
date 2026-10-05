#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

# trust the mirror.lsck0.dev signing key before pacman.conf names the repo
fingerprint=$(gpg --show-keys --with-colons archrepo.asc | awk -F: '$1 == "fpr" {print $10; exit}')
sudo pacman-key --add archrepo.asc
sudo pacman-key --lsign-key "$fingerprint"
# LSCK0_SNAPSHOT=<YYYY-MM-DD> (platform file or env) pins [lsck0] to that night's dated snapshot instead of the latest
[[ "${LSCK0_SNAPSHOT:-}" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})?$ ]] || { echo "pacman: LSCK0_SNAPSHOT '$LSCK0_SNAPSHOT' is not YYYY-MM-DD" >&2; exit 1; }
# [lsck0] always, so an unreachable snapshot fails the sync instead of mixing live core with snapshot sonames; rename, never a half-written file
sed "/^\[lsck0\]/,/^\[/ s|/\$arch\$|${LSCK0_SNAPSHOT:+/$LSCK0_SNAPSHOT}/\$arch|" pacman.conf | sudo install -m644 /dev/stdin /etc/pacman.conf.new
sudo mv -f /etc/pacman.conf.new /etc/pacman.conf
mkdir -p "${HOME}/.config/pacman"
ln -sfn "${PWD}/makepkg.conf" "${HOME}/.config/pacman/makepkg.conf"

# hooks run as root: root-owned copies with @USER@ filled in, never links into the checkout
for hook in hooks/*.hook; do
    sed "s|@USER@|$(id -un)|" "${hook}" | sudo install -Dm644 /dev/stdin "/etc/pacman.d/hooks/${hook#hooks/}"
done

# yay cache cleanup
mkdir -p "${HOME}/.config/systemd/user"
ln -sfn "${PWD}/yay-cache-clean.service" "${HOME}/.config/systemd/user/yay-cache-clean.service"
ln -sfn "${PWD}/yay-cache-clean.timer" "${HOME}/.config/systemd/user/yay-cache-clean.timer"
systemctl --user daemon-reload
systemctl --user enable --now yay-cache-clean.timer
