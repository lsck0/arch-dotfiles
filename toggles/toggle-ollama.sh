#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

check() { systemctl is-active --quiet ollama.service && echo on || echo off; }
turn_on() { sudo systemctl start ollama.service; }
turn_off() { sudo systemctl stop ollama.service; }

toggle_main ollama "Ollama" check turn_on turn_off "${1:-toggle}"
