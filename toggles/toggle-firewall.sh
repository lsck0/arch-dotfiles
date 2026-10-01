#!/usr/bin/env bash
# 3-state firewall: default (nftables + portmaster), restrictive (lockdown, nothing in), off (no firewall).
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

STATES=(default restrictive off)
ICONS=(🛡 🔒 ⛔)
LABELS=("Default" "Restrictive" "Off")

# no marker means the boot default: firewall on
current() { local s; s=$(toggle_get_volatile firewall); [[ "$s" == off ]] && echo default || echo "$s"; }

index_of() {
    for i in "${!STATES[@]}"; do [[ "${STATES[$i]}" == "$1" ]] && { echo "$i"; return; }; done
    echo 0
}

apply() {
    local state=$1
    case "$state" in
        default)
            sudo systemctl reload-or-restart fw-inbound.service
            sudo systemctl start portmaster.service
            ;;
        restrictive)
            sudo nft -f /etc/nftables.d/fw-lockdown.nft
            sudo systemctl start portmaster.service
            ;;
        off)
            sudo systemctl stop fw-inbound.service portmaster.service || true
            sudo nft delete table inet fw 2>/dev/null || true
            ;;
    esac
    toggle_set_volatile firewall "$state"
    toggle_set firewall "$state"
    toggle_notify -a Toggles "Firewall" "${LABELS[$(index_of "$state")]}"
}

action=${1:-toggle}
state=$(current)
idx=$(index_of "$state")

case "$action" in
    get) echo "$state" ;;
    label) echo "${ICONS[$idx]} Firewall: ${LABELS[$idx]}" ;;
    toggle) apply "${STATES[$(((idx + 1) % ${#STATES[@]}))]}" ;;
    default | restrictive | off) apply "$action" ;;
    *) echo "usage: $(basename "$0") {get|label|toggle|default|restrictive|off}" >&2; exit 1 ;;
esac
