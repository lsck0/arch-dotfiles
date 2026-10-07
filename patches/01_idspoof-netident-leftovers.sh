#!/usr/bin/env bash
# undo what the old persona dispatcher's `idspoof apply --netident` left behind, now that the dispatcher no longer uses idspoof

set -euo pipefail

NM_CONF=/etc/NetworkManager/conf.d/90-idspoof-persona.conf
DHCLIENT_HOOK=/etc/dhcp/dhclient-enter-hooks.d/idspoof-vendor

# its sysctls and the reader-less IDSPOOF_NETEMU nfqueue rule
command -v idspoof >/dev/null && { sudo idspoof restore --netident -q || true; }
[[ -e "$NM_CONF" || -e "$DHCLIENT_HOOK" ]] || exit 0
sudo rm -f "$NM_CONF" "$DHCLIENT_HOOK"
