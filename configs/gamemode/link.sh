#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v gamemoded >/dev/null 2>&1; then
    exit 0
fi

set -e

ln -sfn "${PWD}/gamemode.ini" "${HOME}/.config/gamemode.ini"

sudo mkdir -p /etc/sysctl.d
sudo install -m644 sysctl-gamemode.conf /etc/sysctl.d/99-gamemode.conf
sudo sysctl -q -p /etc/sysctl.d/99-gamemode.conf
