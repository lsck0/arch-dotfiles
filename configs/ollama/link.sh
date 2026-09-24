#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v ollama >/dev/null 2>&1; then
    exit 0
fi

set -ex

# Drop-in so ollama keeps models loaded (fast minuet completion).
sudo mkdir -p /etc/systemd/system/ollama.service.d
sudo ln -sfn "${PWD}/keep-alive.conf" /etc/systemd/system/ollama.service.d/keep-alive.conf
sudo systemctl daemon-reload
systemctl is-active --quiet ollama && sudo systemctl restart ollama || true
