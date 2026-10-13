#!/usr/bin/env bash
# wake luca-pc over the homelab: the always-on lab router (luca-router) emits the magic packet with its `wol-pc`, then
# ssh in once it is up. needs the homelab reachable (at home, or `wg-quick up` the homelab tunnel first) and luca-pc's
# firmware "Wake on LAN"/"Power On by PCIe" enabled. the laptop's key must be authorized as root on the router.
set -euo pipefail

ROUTER=192.168.178.29
PC=192.168.178.138

ssh -o ConnectTimeout=5 root@"$ROUTER" wol-pc
echo "wake-pc: magic packet sent, waiting for ${PC} ..." >&2
for _ in $(seq 1 45); do
    if ssh -o ConnectTimeout=3 -o BatchMode=yes luca@"$PC" true 2>/dev/null; then exec ssh luca@"$PC"; fi
    sleep 2
done
echo "wake-pc: ${PC} did not answer ssh within ~90s" >&2
exit 1
