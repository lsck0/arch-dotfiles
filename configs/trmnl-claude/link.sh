#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

# without the UUID the timer would fail every 15 minutes for nothing
if [[ ! -r ../secrets/trmnl-claude.env ]]; then
    echo "configs/trmnl-claude: no ../secrets/trmnl-claude.env, skipping" >&2
    exit 0
fi

set -ex

mkdir -p "${HOME}/.config/systemd/user"
ln -sfn "${PWD}/trmnl-claude.service" "${HOME}/.config/systemd/user/trmnl-claude.service"
ln -sfn "${PWD}/trmnl-claude.timer" "${HOME}/.config/systemd/user/trmnl-claude.timer"

systemctl --user daemon-reload
systemctl --user enable --now trmnl-claude.timer
