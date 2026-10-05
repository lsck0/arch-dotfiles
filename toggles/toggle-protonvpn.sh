#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

check() { ip link show proton0 &>/dev/null && echo on || echo off; }

# portmaster comes back only if the firewall toggle wants it
portmaster_restore() { [[ "$(./toggle-firewall.sh get)" == off ]] || sudo systemctl start portmaster.service; }

turn_on() {
  # protonvpn's own networkmanager kill switch: routes only, owns no nft table
  protonvpn config set kill-switch standard >/dev/null 2>&1
  # portmaster's connmark restore overwrites the wireguard fwmark, so tunnel packets would loop back into proton0
  sudo systemctl stop portmaster.service
  local out
  out=$(protonvpn connect --country CH 2>&1) || true
  if grep -qi "Authentication required" <<<"$out"; then
    notify-send -a Toggles -u critical "ProtonVPN" "Not signed in, run 'protonvpn signin' in a terminal first"
  fi
  [[ "$(check)" == on ]] || portmaster_restore
}
turn_off() {
  protonvpn disconnect >/dev/null 2>&1
  portmaster_restore
}

toggle_main protonvpn "ProtonVPN" check turn_on turn_off "${1:-toggle}"
