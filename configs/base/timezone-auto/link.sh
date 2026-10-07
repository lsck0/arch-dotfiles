#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

mkdir -p "${HOME}/.config/systemd/user"

ln -sfn "${PWD}/timezone-auto.service" "${HOME}/.config/systemd/user/timezone-auto.service"
ln -sfn "${PWD}/timezone-auto.timer" "${HOME}/.config/systemd/user/timezone-auto.timer"
sudo install -m644 49-timezone-auto.rules /etc/polkit-1/rules.d/49-timezone-auto.rules
# wsl has no networkmanager (hardware group); NM refuses a group/world-writable dispatcher
if [[ -d /etc/NetworkManager/dispatcher.d ]]; then
    sed "s|@USER@|$(id -un)|" nm-dispatcher.sh | sudo install -o root -g root -m755 /dev/stdin /etc/NetworkManager/dispatcher.d/85-timezone-auto
fi

systemctl --user daemon-reload
systemctl --user enable --now timezone-auto.timer

# offline is fine here, the next network change retries
"${PWD}/timezone-auto.sh" check || true
