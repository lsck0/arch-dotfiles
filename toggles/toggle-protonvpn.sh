#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

check() { ip link show proton0 &>/dev/null && echo on || echo off; }

# stop portmaster: its nfqueue interception breaks protonvpn's fwmark routing (no traffic flows)
turn_on() {
  sudo systemctl stop portmaster.service
  sudo ufw --force reset >/dev/null
  sudo ufw default deny incoming >/dev/null
  sudo ufw default allow outgoing >/dev/null
  sudo ufw default allow routed >/dev/null
  sudo ufw allow ssh >/dev/null
  sudo ufw allow http >/dev/null
  sudo ufw allow https >/dev/null
  sudo ufw --force enable >/dev/null
  local out
  out=$(protonvpn connect --country CH 2>&1) || true
  if grep -qi "Authentication required" <<<"$out"; then
    notify-send -a Toggles -u critical "ProtonVPN" "Not signed in — run 'protonvpn signin' in a terminal first"
  fi
}
turn_off() {
  protonvpn disconnect >/dev/null 2>&1
  sudo ufw --force disable >/dev/null 2>&1
  sudo systemctl start portmaster.service
}

toggle_main protonvpn "ProtonVPN" check turn_on turn_off "${1:-toggle}"
