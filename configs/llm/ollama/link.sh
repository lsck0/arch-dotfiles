#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

# copied, not linked: pid1 loads drop-ins before /home mounts
sudo rm -f /etc/systemd/system/ollama.service.d/keep-alive.conf
sudo install -Dm644 "${PWD}/keep-alive.conf" /etc/systemd/system/ollama.service.d/keep-alive.conf
sudo systemctl daemon-reload
if systemctl is-active --quiet ollama; then sudo systemctl restart ollama; fi

# models are pulled lazily on first use, never here: keeps config.sh off the GB download path
chmod 755 "${PWD}/ollama-ensure-models.sh"
ln -sfn "${PWD}/ollama-ensure-models.sh" "${HOME}/.local/bin/ollama-ensure-models"
