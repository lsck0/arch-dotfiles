#!/usr/bin/env bash
# Connect to an SSID: `network-wifi-connect.sh <ssid> [password]`.
set -euo pipefail

ssid="${1:?ssid required}"
password="${2:-}"

if [[ -n "$password" ]]; then
  nmcli dev wifi connect "$ssid" password "$password"
else
  nmcli dev wifi connect "$ssid"
fi
