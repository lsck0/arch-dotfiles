#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

toggle_service ollama "Ollama" ollama.service "${1:-toggle}"
