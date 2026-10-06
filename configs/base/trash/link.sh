#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

# weekly trash cleanup, home trash and the tmpfs trash
install -Dm644 ./trash-empty.service ~/.config/systemd/user/trash-empty.service
install -Dm644 ./trash-empty.timer ~/.config/systemd/user/trash-empty.timer
systemctl --user daemon-reload
systemctl --user enable --now trash-empty.timer
