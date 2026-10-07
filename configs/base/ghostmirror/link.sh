#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

source $DOTFILES/scripts/lib/personal.sh

HOMELAB_MIRROR=10.100.0.109

# the committed ranking seeds a fresh install or replaces the old link into the checkout; the timers keep it current
if [[ -L /etc/pacman.d/mirrorlist ]] || ! grep -q '^# lastsync' /etc/pacman.d/mirrorlist; then
    # guests get no homelab mirror
    if is_personal; then
        sudo install -Dm644 mirrorlist /etc/pacman.d/mirrorlist
    else
        grep -vF "$HOMELAB_MIRROR" mirrorlist | sudo install -Dm644 /dev/stdin /etc/pacman.d/mirrorlist
    fi
elif ! is_personal && grep -qF "$HOMELAB_MIRROR" /etc/pacman.d/mirrorlist; then
    # an older run seeded it before the guest gate; mirrorlist-update.sh keeps only a homelab line that is present
    grep -vF "$HOMELAB_MIRROR" /etc/pacman.d/mirrorlist | sudo install -m644 /dev/stdin /etc/pacman.d/mirrorlist.new
    sudo mv -f /etc/pacman.d/mirrorlist.new /etc/pacman.d/mirrorlist
fi

# root writes the mirrorlist, so root runs the ranking from a root-owned copy; weekly sort re-ranks, monthly rebuild finds new mirrors
sudo install -Dm755 mirrorlist-update.sh /usr/local/bin/mirrorlist-update
for unit in ghostmirror.service ghostmirror.timer ghostmirror-refresh.service ghostmirror-refresh.timer; do
    sudo install -Dm644 "$unit" "/etc/systemd/system/$unit"
done
sudo systemctl daemon-reload
sudo systemctl enable --now ghostmirror.timer ghostmirror-refresh.timer
