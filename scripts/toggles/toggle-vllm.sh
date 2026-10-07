#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# on means vllm.socket listens and cold-starts the server on the first request; off also frees the VRAM.
check() { systemctl is-active --quiet vllm.socket && echo on || echo off; }
turn_on() { toggle_root vllm on; }
turn_off() { toggle_root vllm off; }

toggle_main vllm "vLLM" check turn_on turn_off "${1:-toggle}"
