#!/usr/bin/env bash

if ! command -v rocminfo >/dev/null 2>&1; then
    exit 0
fi

if ! rocminfo 2>/dev/null | grep -q '^Agent [0-9]*.*$' || ! rocminfo 2>/dev/null | grep -q 'gfx[0-9a-f]\{3,\}'; then
    exit 0
fi

set -ex

chmod 755 "${PWD}/vllm-wait-ready.sh"

sudo cp "${PWD}/vllm-proxy.service" /etc/systemd/system/vllm-proxy.service
sudo cp "${PWD}/vllm.service" /etc/systemd/system/vllm.service
sudo cp "${PWD}/vllm.socket" /etc/systemd/system/vllm.socket

sudo systemctl daemon-reload
sudo systemctl enable --now vllm.socket
