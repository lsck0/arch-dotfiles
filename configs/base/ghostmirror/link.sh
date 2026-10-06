#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

# the committed ranking seeds a fresh install or replaces the old link into the checkout; the timers keep it current
if [[ -L /etc/pacman.d/mirrorlist ]] || ! grep -q '^# lastsync' /etc/pacman.d/mirrorlist; then
    sudo install -Dm644 mirrorlist /etc/pacman.d/mirrorlist
fi

# root writes the mirrorlist, so root runs the ranking from a root-owned copy; weekly sort re-ranks, monthly rebuild finds new mirrors
sudo install -Dm755 mirrorlist-update.sh /usr/local/bin/mirrorlist-update
for unit in ghostmirror.service ghostmirror.timer ghostmirror-refresh.service ghostmirror-refresh.timer; do
    sudo install -Dm644 "$unit" "/etc/systemd/system/$unit"
done
sudo systemctl daemon-reload
sudo systemctl enable --now ghostmirror.timer ghostmirror-refresh.timer
