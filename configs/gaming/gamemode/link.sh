#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

ln -sfn "${PWD}/gamemode.ini" "${HOME}/.config/gamemode.ini"

sudo mkdir -p /etc/sysctl.d
sudo install -m644 sysctl-gamemode.conf /etc/sysctl.d/99-gamemode.conf
sudo sysctl -q -p /etc/sysctl.d/99-gamemode.conf

# the hook stops vllm/ollama to free vram; polkit lets it manage those system units unprompted
if [[ -d /etc/polkit-1/rules.d ]]; then
    sudo install -m644 49-gamemode-services.rules /etc/polkit-1/rules.d/49-gamemode-services.rules
fi
