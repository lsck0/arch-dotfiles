#!/usr/bin/env bash
# undo what the old persona dispatcher's `idspoof apply --netident` left behind, now that the dispatcher no longer uses idspoof

set -euo pipefail

NM_CONF=/etc/NetworkManager/conf.d/90-idspoof-persona.conf
DHCLIENT_HOOK=/etc/dhcp/dhclient-enter-hooks.d/idspoof-vendor

# its files mark a machine it ran on; without them a restore would undo nothing of ours
[[ -e "$NM_CONF" || -e "$DHCLIENT_HOOK" ]] || exit 0
# its sysctls and the reader-less IDSPOOF_NETEMU nfqueue rule
if command -v idspoof >/dev/null; then idspoof restore --netident -q || true; fi
rm -f "$NM_CONF" "$DHCLIENT_HOOK"
