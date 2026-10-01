#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

# journald size cap; restart only on change, a restart rotates the running journal.
# a real file: journald and pid1 read /etc before /home is mounted, so a symlink into the repo dangles at boot
journald_conf=/etc/systemd/journald.conf.d/00-size.conf
if ! cmp -s "${PWD}/journald-size.conf" "${journald_conf}" || [ -L "${journald_conf}" ]; then
    sudo rm -f "${journald_conf}"
    sudo install -Dm644 "${PWD}/journald-size.conf" "${journald_conf}"
    sudo systemctl restart systemd-journald.service
fi

# nix store gc; daemon install means root collects system-wide
if command -v nix >/dev/null 2>&1; then
    sudo rm -f /etc/systemd/system/nix-gc.service /etc/systemd/system/nix-gc.timer
    sudo install -Dm644 "${PWD}/nix-gc.service" /etc/systemd/system/nix-gc.service
    sudo install -Dm644 "${PWD}/nix-gc.timer" /etc/systemd/system/nix-gc.timer
    sudo systemctl daemon-reload
    sudo systemctl enable --now nix-gc.timer
fi

# user trash auto-empty
if command -v trash-empty >/dev/null 2>&1; then
    mkdir -p "${HOME}/.config/systemd/user"
    ln -sfn "${PWD}/trash-empty.service" "${HOME}/.config/systemd/user/trash-empty.service"
    ln -sfn "${PWD}/trash-empty.timer" "${HOME}/.config/systemd/user/trash-empty.timer"
    systemctl --user daemon-reload
    systemctl --user enable --now trash-empty.timer
fi
