#!/usr/bin/env bash

set -euo pipefail

IFACE="enp16s0"

# MAC=$(printf '%02x:%02x:%02x:%02x:%02x:%02x' \
#     $(( (RANDOM & 0xfc) | 0x02 )) \
#     $(( RANDOM & 0xff )) $(( RANDOM & 0xff )) \
#     $(( RANDOM & 0xff )) $(( RANDOM & 0xff )) $(( RANDOM & 0xff )))
# MAC="10:FF:E0:E4:04:4A" # original mac
MAC="2C:F0:5D:D9:EC:56"  # server mac

sudo ip link set dev "$IFACE" down
sudo ip link set dev "$IFACE" address "$MAC"
sudo ip link set dev "$IFACE" up

echo "$IFACE -> $(cat "/sys/class/net/$IFACE/address")"
