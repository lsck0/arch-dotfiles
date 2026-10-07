#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

ln -sfn "${PWD}" "${HOME}/.config/idle-guards"
mkdir -p "${HOME}/.config/systemd/user"
for unit in idle-guard-media.service idle-guard-ssh.service; do
    ln -sfn "${PWD}/${unit}" "${HOME}/.config/systemd/user/${unit}"
done
systemctl --user daemon-reload
systemctl --user enable idle-guard-media.service idle-guard-ssh.service
