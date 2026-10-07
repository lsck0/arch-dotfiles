#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

# journald size cap; restart only on change, a restart rotates the running journal
journald_conf=/etc/systemd/journald.conf.d/00-size.conf
if ! cmp -s "${PWD}/journald-size.conf" "${journald_conf}" || [ -L "${journald_conf}" ]; then
    # copied, not linked: journald reads /etc before /home mounts
    sudo rm -f "${journald_conf}"
    sudo install -Dm644 "${PWD}/journald-size.conf" "${journald_conf}"
    sudo systemctl restart systemd-journald.service
fi

# runs as the profile owner: expires its generations, the daemon collects the store
if command -v nix >/dev/null 2>&1; then
    if [ -e /etc/systemd/system/nix-gc.timer ]; then
        sudo systemctl disable --now nix-gc.timer
        sudo rm -f /etc/systemd/system/nix-gc.{service,timer}
        sudo systemctl daemon-reload
    fi
    install -Dm644 "${PWD}/nix-gc.service" "${HOME}/.config/systemd/user/nix-gc.service"
    install -Dm644 "${PWD}/nix-gc.timer" "${HOME}/.config/systemd/user/nix-gc.timer"
    systemctl --user daemon-reload
    systemctl --user enable --now nix-gc.timer
fi

