#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

toggle_radio wifi "Wi-Fi" wifi "${1:-toggle}"
