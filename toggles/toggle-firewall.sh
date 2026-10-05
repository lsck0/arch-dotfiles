#!/usr/bin/env bash
# 3-state firewall: default (fw-inbound + portmaster), restrictive (fw-lockdown + portmaster), off (neither).
# State is read back from the units, so a reboot, config.sh or a failed unit is reported as it is.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

STATES=(default restrictive off)
LABELS=("Default" "Restrictive" "Off")

current() {
    if systemctl is-active --quiet fw-lockdown.service; then
        echo restrictive
    elif systemctl is-active --quiet fw-inbound.service; then
        echo default
    else
        echo off
    fi
}

# portmaster's connmark restore clobbers protonvpn's wireguard fwmark, so toggle-protonvpn.sh owns it while proton0 is up
portmaster_start() {
    ip link show proton0 &>/dev/null || sudo systemctl start portmaster.service
}

apply() {
    local state=$1
    case "$state" in
        default)
            # conflicts with fw-lockdown, which systemd stops first
            sudo systemctl start fw-inbound.service
            portmaster_start
            ;;
        restrictive)
            sudo systemctl start fw-lockdown.service
            portmaster_start
            ;;
        off)
            sudo systemctl stop fw-inbound.service fw-lockdown.service portmaster.service
            ;;
    esac
    toggle_notify -a Toggles "Firewall" "${LABELS[$(toggle_index_of "$(current)" 0 "${STATES[@]}")]}"
}

action=${1:-toggle}
state=$(current)
idx=$(toggle_index_of "$state" 0 "${STATES[@]}")

case "$action" in
    get) echo "$state" ;;
    label)
        suffix=""
        # portmaster and the nft table should agree; say so when they don't
        if [[ "$state" != off ]] && ! systemctl is-active --quiet portmaster.service; then
            suffix=" (Portmaster off)"
        elif [[ "$state" == off ]] && systemctl is-active --quiet portmaster.service; then
            suffix=" (Portmaster on)"
        fi
        if [[ "$state" == off ]]; then echo "○ Firewall: ${LABELS[$idx]}$suffix"; else echo "● Firewall: ${LABELS[$idx]}$suffix"; fi
        ;;
    toggle) apply "${STATES[$(((idx + 1) % ${#STATES[@]}))]}" ;;
    default | restrictive | off) apply "$action" ;;
    *) echo "usage: $(basename "$0") {get|label|toggle|default|restrictive|off}" >&2; exit 1 ;;
esac
