#!/usr/bin/env bash
# Connect to an SSID: `network-wifi-connect.sh <ssid> [password]`. No
# password touches disk here — it goes straight to nmcli's argv, same as
# typing `nmcli dev wifi connect` by hand. NetworkManager stores the PSK in
# its own connection profile (root-owned, under /etc/NetworkManager), not
# this repo.
set -euo pipefail

ssid="${1:?ssid required}"
password="${2:-}"

if [[ -n "$password" ]]; then
  nmcli dev wifi connect "$ssid" password "$password"
else
  nmcli dev wifi connect "$ssid"
fi
