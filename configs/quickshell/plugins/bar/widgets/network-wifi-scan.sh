#!/usr/bin/env bash
# json array of nearby wifi networks
set -euo pipefail

if [[ "${1:-}" == "rescan" ]]; then
  nmcli dev wifi rescan 2>/dev/null || true
  sleep 1.5
fi

# ssid last and unescaped, so colons in it stay part of it
nmcli -t -e no -f ACTIVE,SIGNAL,SECURITY,SSID dev wifi list 2>/dev/null \
  | jq -Rnc '
    [inputs
      | capture("^(?<active>[^:]*):(?<signal>[^:]*):(?<security>[^:]*):(?<ssid>.*)$")
      | select(.ssid != "")]
    | reduce .[] as $n ([]; if any(.[]; .ssid == $n.ssid) then . else . + [$n] end)
    | map({active: (.active == "yes"), ssid, signal: (.signal | tonumber? // 0), secure: (.security != "" and .security != "--")})
  '
