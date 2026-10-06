#!/usr/bin/env bash
# utc offset in seconds per zone, polled so dst changes are picked up
set -euo pipefail

# label:iana-zone
zones=(
  "Central Europe:Europe/Berlin"
  "UK:Europe/London"
  "USA East:America/New_York"
  "USA Central:America/Chicago"
  "USA West:America/Los_Angeles"
  "New Zealand:Pacific/Auckland"
)

out="["
first=1
for entry in "${zones[@]}"; do
  label=${entry%%:*}
  z=${entry#*:}
  offset_str=$(TZ="$z" date +%z)
  sign=${offset_str:0:1}
  hh=${offset_str:1:2}
  mm=${offset_str:3:2}
  secs=$((10#$hh * 3600 + 10#$mm * 60))
  [[ "$sign" == "-" ]] && secs=$((-secs))
  [[ $first -eq 0 ]] && out+=","
  out+="{\"zone\":\"$label\",\"offsetSec\":$secs}"
  first=0
done
out+="]"
echo "$out"
