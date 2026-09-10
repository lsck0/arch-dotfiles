#!/bin/bash
# Verbatim from omarchy's bin/omarchy-network-speedtest except:
# `omarchy-cmd-present curl` -> `command -v curl` (no local equivalent of
# that helper, and this is the only place it was used).
#
# Measures live internet speed for one direction against fast.com's (Netflix)
# speedtest CDN, printing one Mbps reading per second until killed. Used by
# configs/quickshell/plugins/speedtest/Panel.qml, which runs it for a fixed
# window per direction (see phaseTimer) and SIGTERMs it between phases.

set -e

direction="${1:-}"
probe=1.1.1.1
parallel=8
url_count=3
curl_common=(--fail --silent --show-error --connect-timeout 3 --max-time 20 --ipv4)

case "$direction" in
  down | up)
    ;;
  *)
    echo "Usage: network-speedtest.sh [down|up]" >&2
    exit 2
    ;;
esac

format_mbps() {
  awk -v value="$1" 'BEGIN {
    if (value <= 0) print "0.0"
    else if (value < 10) printf "%.1f\n", value
    else printf "%.0f\n", value
  }'
}

iface=$(ip route get "$probe" 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }')

if [[ -z $iface || ! -r /sys/class/net/$iface/statistics/rx_bytes || ! -r /sys/class/net/$iface/statistics/tx_bytes ]]; then
  echo "No active network interface" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required" >&2
  exit 1
fi

fast_token="YXNkZmFzZGxmbnNkYWZoYXNkZmhrYWxm"
fast_api_url="https://api.fast.com/netflix/speedtest/v2?https=true&token=$fast_token&urlCount=$url_count"

if ! fast_urls=$(curl "${curl_common[@]}" "$fast_api_url" 2>/dev/null | jq -r '.targets[]?.url // empty'); then
  echo "Failed to fetch speed test endpoints" >&2
  exit 1
fi

if [[ -z $fast_urls ]]; then
  echo "Failed to fetch speed test endpoints" >&2
  exit 1
fi

traffic_pids=()

cleanup() {
  local pid
  for pid in "${traffic_pids[@]}"; do
    [[ -n $pid ]] || continue
    pkill -TERM -P "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
  done
  for pid in "${traffic_pids[@]}"; do
    [[ -n $pid ]] || continue
    wait "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT

# Round-robin across the returned URLs so we spread load across Netflix OCA nodes.
traffic_worker() {
  local urls=("$@")
  local url_count=${#urls[@]}
  local idx=$RANDOM
  if [[ $direction == "down" ]]; then
    while true; do
      url=${urls[$((idx % url_count))]}
      curl "${curl_common[@]}" -o /dev/null "$url" 2>/dev/null || return
      idx=$((idx + 1))
    done
  else
    while true; do
      url=${urls[$((idx % url_count))]}
      dd if=/dev/zero bs=1M count=64 2>/dev/null | curl "${curl_common[@]}" -o /dev/null -X POST --data-binary @- "$url" 2>/dev/null || return
      idx=$((idx + 1))
    done
  fi
}

for (( i = 0; i < parallel; i++ )); do
  traffic_worker $fast_urls &
  traffic_pids+=("$!")
done

rx_before=$(cat "/sys/class/net/$iface/statistics/rx_bytes")
tx_before=$(cat "/sys/class/net/$iface/statistics/tx_bytes")

any_alive() {
  local pid
  for pid in "${traffic_pids[@]}"; do
    [[ -n $pid ]] || continue
    if kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

while any_alive; do
  sleep 1
  rx_after=$(cat "/sys/class/net/$iface/statistics/rx_bytes")
  tx_after=$(cat "/sys/class/net/$iface/statistics/tx_bytes")

  if [[ $direction == "down" ]]; then
    rate=$(awk -v before="$rx_before" -v after="$rx_after" 'BEGIN {
      if (after < before) print 0
      else print (after - before) * 8 / 1000000
    }')
  else
    rate=$(awk -v before="$tx_before" -v after="$tx_after" 'BEGIN {
      if (after < before) print 0
      else print (after - before) * 8 / 1000000
    }')
  fi

  format_mbps "$rate"
  rx_before=$rx_after
  tx_before=$tx_after
done

wait 2>/dev/null || true
