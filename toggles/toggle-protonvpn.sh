#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# protonvpn (the proton-vpn-cli package) prints a noisy eventlet deprecation
# warning on every invocation; filter it rather than let it pollute get/label.
# check() uses the proton0 interface, not `protonvpn status`, on purpose:
# that CLI call takes ~1.2-1.4s of near-100%-CPU Python startup per
# invocation, and the bar polls check() every 10s — that alone was the
# "periodic 100% CPU spike", independent of the separate Portmaster
# connectivity bug. Matches toggle-vpn.sh's `ip link show wg0` pattern.
check() { ip link show proton0 &>/dev/null && echo on || echo off; }

# portmaster.service (the system's normal firewall) has an unresolved upstream
# conflict with ProtonVPN's WireGuard tunnel: its NFQUEUE packet interception
# fights ProtonVPN's fwmark-based policy routing, so the tunnel comes up but
# no traffic ever actually flows through it. Confirmed live (stopping
# portmaster.service is the only thing that's ever fixed it) and matches
# Safing's own still-open tracker (github.com/safing/portmaster/issues/1246);
# Safing has explicitly declined to add VPN-client compatibility (issues
# #1651, #734, #777) and there's no settings-level fix — see TODO.md. So the
# only way to actually use ProtonVPN here is to stop portmaster.service around
# the connection. To not go fully unfirewalled in the meantime, ufw (already
# installed, otherwise unused) stands in as a basic default-deny-incoming
# backstop — not Portmaster's app-level/DNS filtering, but real coverage
# instead of none. Mirrors portmaster's own current inbound allowlist
# (configs/portmaster/config.json's serviceEndpoints: 22/80/443) so the
# effective inbound policy doesn't change during the gap.
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
