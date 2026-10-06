#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# WWAN radio via nmcli; needs ModemManager (enabled in networkmanager/link.sh)
toggle_radio mobile "Mobile" wwan "${1:-toggle}"
