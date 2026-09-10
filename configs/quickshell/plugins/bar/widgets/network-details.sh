#!/usr/bin/env bash
# One-shot JSON snapshot of the active connection's device/IP/MAC and
# instantaneous up/down throughput, for Network.qml's details row. Rate is a
# two-sample delta over 0.3s, same shape as system-stats.sh's CPU%/GPU% —
# /proc/net/dev has no instantaneous rate, only cumulative byte counters.
set -euo pipefail

# NetworkManager's own connectivity verdict: full | limited | portal | none
# | unknown. This is the honest answer to "do we actually have internet?" --
# a device can be `connected` with a valid IP and still be behind a captive
# portal or a link with no route out, which a device-state check reports as
# online. Rendered separately from `connected` for exactly that reason.
connectivity=$(nmcli -t -f CONNECTIVITY general 2>/dev/null || echo unknown)
connectivity=${connectivity:-unknown}

device=$(nmcli -t -f DEVICE,STATE dev status 2>/dev/null | awk -F: '$2 == "connected" && $1 != "lo" {print $1; exit}')
device=${device:-}

if [[ -z "$device" ]]; then
  jq -nc --arg c "$connectivity" '{connected: false, connectivity: $c}'
  exit 0
fi

ssid=$(nmcli -t -f GENERAL.CONNECTION dev show "$device" 2>/dev/null | cut -d: -f2-)
ip4=$(nmcli -t -f IP4.ADDRESS dev show "$device" 2>/dev/null | head -1 | cut -d: -f2-)
mac=$(cat "/sys/class/net/$device/address" 2>/dev/null || echo "")

rx1=$(cat "/sys/class/net/$device/statistics/rx_bytes" 2>/dev/null || echo 0)
tx1=$(cat "/sys/class/net/$device/statistics/tx_bytes" 2>/dev/null || echo 0)
sleep 0.3
rx2=$(cat "/sys/class/net/$device/statistics/rx_bytes" 2>/dev/null || echo 0)
tx2=$(cat "/sys/class/net/$device/statistics/tx_bytes" 2>/dev/null || echo 0)

rx_kbps=$(awk -v a="$rx1" -v b="$rx2" 'BEGIN { printf "%.0f", (b - a) / 0.3 / 1024 }')
tx_kbps=$(awk -v a="$tx1" -v b="$tx2" 'BEGIN { printf "%.0f", (b - a) / 0.3 / 1024 }')

jq -nc --arg device "$device" --arg ssid "$ssid" --arg ip4 "$ip4" --arg mac "$mac" \
  --arg rx "$rx_kbps" --arg tx "$tx_kbps" --arg c "$connectivity" \
  '{connected: true, connectivity: $c, device: $device, ssid: $ssid, ip4: $ip4, mac: $mac, rxKbps: ($rx | tonumber), txKbps: ($tx | tonumber)}'
