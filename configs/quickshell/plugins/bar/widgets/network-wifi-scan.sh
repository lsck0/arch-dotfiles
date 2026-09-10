#!/usr/bin/env bash
# JSON array of nearby Wi-Fi networks for Network.qml's SSID list.
# `nmcli dev wifi list` uses cached scan results (fast); pass "rescan" as $1
# to force a fresh scan first (slower, ~2-5s).
set -euo pipefail

if [[ "${1:-}" == "rescan" ]]; then
  nmcli dev wifi rescan 2>/dev/null || true
  sleep 1.5
fi

nmcli -t -f ACTIVE,SSID,SIGNAL,SECURITY dev wifi list 2>/dev/null \
  | awk -F: '
    BEGIN { print "[" }
    $2 != "" {
      if (seen[$2]++) next
      if (n++ > 0) printf ","
      gsub(/"/, "\\\"", $2)
      printf "{\"active\":%s,\"ssid\":\"%s\",\"signal\":%s,\"secure\":%s}",
        ($1 == "yes" ? "true" : "false"), $2, ($3 == "" ? 0 : $3), ($4 == "" ? "false" : "true")
    }
    END { print "]" }
  '
