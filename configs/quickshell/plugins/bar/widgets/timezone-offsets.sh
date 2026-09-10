#!/usr/bin/env bash
# UTC offset (seconds) for each configured zone, refreshed periodically by
# Clock.qml so DST transitions get picked up without a subprocess per tick.
set -euo pipefail

# label:IANA-zone pairs. Glasgow, NA west/east coast, NZ.
zones=(
  "Glasgow:Europe/London"
  "NA West:America/Los_Angeles"
  "NA East:America/New_York"
  "NZ:Pacific/Auckland"
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
