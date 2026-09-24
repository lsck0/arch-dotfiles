#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# protonvpn (the proton-vpn-cli package) prints a noisy eventlet deprecation warning on every invocation; filter it rather than let it pollute get/label.
check() { ip link show proton0 &>/dev/null && echo on || echo off; }

# portmaster.service (the system's normal firewall) has an unresolved upstream conflict with ProtonVPN's WireGuard tunnel: its NFQUEUE packet interception fights ProtonVPN's fwmark-based policy routing, so the tunnel comes up but no traffic ever actually flows through it.
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
  out=$(protonvpn connect 2>&1) || true
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
