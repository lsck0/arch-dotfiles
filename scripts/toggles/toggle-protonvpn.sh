#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

check() { ip link show proton0 &>/dev/null && echo on || echo off; }

# portmaster comes back only if the firewall toggle wants it; systemctl (polkit) so auto-vpn works unattended
portmaster_restore() { [[ "$(./toggle-firewall.sh get)" == off ]] || systemctl --no-ask-password start portmaster.service; }

turn_on() {
  # protonvpn's own networkmanager kill switch: routes only, owns no nft table. set only when unset, a user's choice stays
  # config list shows unset as off, so the settings file is the only place unset is visible
  jq -e 'has("killswitch")' "${XDG_CONFIG_HOME:-$HOME/.config}/Proton/VPN/settings.json" &>/dev/null ||
    protonvpn config set kill-switch standard >/dev/null 2>&1 || true
  # portmaster's connmark restore overwrites the wireguard fwmark, so tunnel packets would loop back into proton0
  systemctl --no-ask-password stop portmaster.service
  local out
  out=$(protonvpn connect --country CH 2>&1) || true
  if grep -qi "Authentication required" <<<"$out"; then
    toggle_notify -a Toggles -u critical "ProtonVPN" "Not signed in, run 'protonvpn signin' in a terminal first"
  fi
  [[ "$(check)" == off ]] || return 0
  # no tunnel: portmaster back, and a failure rather than "Turned on"
  portmaster_restore
  echo "protonvpn: connect failed: $out" >&2
  return 1
}
turn_off() {
  protonvpn disconnect >/dev/null 2>&1
  portmaster_restore
}

toggle_main protonvpn "ProtonVPN" check turn_on turn_off "${1:-toggle}"
