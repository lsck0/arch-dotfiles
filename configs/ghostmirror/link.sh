#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v ghostmirror >/dev/null 2>&1; then
    exit 0
fi

set -ex

# link first, the rebuild writes through it into the repo copy
sudo ln -sfn ${PWD}/mirrorlist /etc/pacman.d/mirrorlist
./mirrorlist-update.sh rebuild

# units installed by hand, not via `ghostmirror -D`
install -Dm644 ./ghostmirror.service ~/.config/systemd/user/ghostmirror.service
install -Dm644 ./ghostmirror.timer ~/.config/systemd/user/ghostmirror.timer

# weekly sort only re-ranks; monthly rebuild picks up new mirrors
install -Dm644 ./ghostmirror-refresh.service ~/.config/systemd/user/ghostmirror-refresh.service
install -Dm644 ./ghostmirror-refresh.timer ~/.config/systemd/user/ghostmirror-refresh.timer

systemctl --user daemon-reload
systemctl --user enable --now ghostmirror.timer
systemctl --user enable --now ghostmirror-refresh.timer
