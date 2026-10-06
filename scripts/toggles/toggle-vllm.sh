#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# on means vllm.socket listens and cold-starts the server on the first request; off also frees the VRAM.
check() { systemctl is-active --quiet vllm.socket && echo on || echo off; }
turn_on() { sudo systemctl enable --now vllm.socket; }
turn_off() {
    sudo systemctl disable --now vllm.socket
    sudo systemctl stop vllm-proxy.service vllm.service
}

toggle_main vllm "vLLM" check turn_on turn_off "${1:-toggle}"
