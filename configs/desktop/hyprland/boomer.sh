#!/usr/bin/env bash
# no_warps while mapping: the monitor-0 window rule would yank the cursor

set -u

warps_off=$(hyprctl -j getoption cursor:no_warps | jq -r '.bool')
restore() { hyprctl eval "hl.config({ cursor = { no_warps = ${warps_off} } })" >/dev/null; }
hyprctl eval 'hl.config({ cursor = { no_warps = true } })' >/dev/null

scale=$(hyprctl -j monitors | jq -r '.[] | select(.focused) | .scale' | head -n1)
grim -t ppm - | wayland-boomer --monitor-scaling "$scale" &

for _ in $(seq 1 60); do
    hyprctl -j clients | jq -e '.[] | select(.title == "wayland-boomer")' >/dev/null && break
    sleep 0.05
done
# focus settles a frame after the map
sleep 0.1
restore
wait
