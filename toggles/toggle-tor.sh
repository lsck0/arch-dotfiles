#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

toggle_service tor "Tor Router" tor-router.service "${1:-toggle}"
