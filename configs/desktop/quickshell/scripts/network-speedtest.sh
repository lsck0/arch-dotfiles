#!/usr/bin/env bash
# fast.com throughput in one run: "name <connection>", "ping <ms>", then "down <Mbps>" and "up <Mbps>" once a second
set -e
source "$(dirname "$(readlink -f "$0")")/lib/speedtest.sh"

probe=1.1.1.1
parallel=8
url_count=3
phase_seconds=5
curl_common=(--fail --silent --show-error --connect-timeout 3 --max-time 20 --ipv4)
fast_token="YXNkZmFzZGxmbnNkYWZoYXNkZmhrYWxm"
fast_api_url="https://api.fast.com/netflix/speedtest/v2?https=true&token=$fast_token&urlCount=$url_count"

iface=$(ip route get "$probe" 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
stats=/sys/class/net/$iface/statistics
if [[ -z $iface || ! -r $stats/rx_bytes || ! -r $stats/tx_bytes ]]; then
  echo "No active network interface" >&2
  exit 1
fi

name=$(nmcli -g GENERAL.CONNECTION device show "$iface" 2>/dev/null || true)
echo "name ${name:-$iface}"
ping -c 1 -W 2 "$probe" 2>/dev/null | sed -nE 's/.*time[=<]([0-9.]+) ms.*/ping \1/p' &

fast_urls=$(curl "${curl_common[@]}" "$fast_api_url" 2>/dev/null | jq -r '.targets[]?.url // empty' || true)
if [[ -z $fast_urls ]]; then
  echo "Failed to fetch speed test endpoints" >&2
  exit 1
fi

trap workers_stop EXIT

# round-robin to spread load across fast.com nodes
traffic_worker() {
  local direction=$1
  shift
  local urls=("$@") idx=$RANDOM url
  while kill -0 $$ 2>/dev/null; do
    url=${urls[$((idx % ${#urls[@]}))]}
    if [[ $direction == down ]]; then
      curl "${curl_common[@]}" -o /dev/null "$url" 2>/dev/null || return
    else
      dd if=/dev/zero bs=1M count=64 2>/dev/null | curl "${curl_common[@]}" -o /dev/null -X POST --data-binary @- "$url" 2>/dev/null || return
    fi
    idx=$((idx + 1))
  done
}

# "<direction> <Mbps>" each second for phase_seconds
measure() {
  local direction=$1 counter=$2 before after samples=0 i
  for (( i = 0; i < parallel; i++ )); do
    traffic_worker "$direction" $fast_urls &
    worker_pids+=("$!")
  done
  before=$(<"$stats/$counter")
  while (( samples < phase_seconds )) && (( $(workers_alive_count) > 0 )); do
    sleep 1
    after=$(<"$stats/$counter")
    echo "$direction $(rate_format "$(awk -v b="$before" -v a="$after" 'BEGIN { print a < b ? 0 : (a - b) * 8 / 1000000 }')")"
    before=$after
    samples=$((samples + 1))
  done
  workers_stop
}

measure down rx_bytes
measure up tx_bytes
