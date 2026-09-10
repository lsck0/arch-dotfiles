#!/usr/bin/env bash
set -euo pipefail

# Message IDs from /usr/lib/systemd/catalog/systemd.catalog:
#   d989611b15e44c9dbf31e3c81256e4ed = systemd-oomd killed a unit on memory pressure
#   fe6faa94e7774663a0da52717891d8ef = kernel OOM killer killed a unit
journalctl --no-pager -f -o json \
    MESSAGE_ID=d989611b15e44c9dbf31e3c81256e4ed \
    MESSAGE_ID=fe6faa94e7774663a0da52717891d8ef |
while IFS= read -r line; do
    id=$(jq -r '.MESSAGE_ID' <<<"$line")
    unit=$(jq -r '.UNIT // "unknown unit"' <<<"$line")
    msg=$(jq -r '.MESSAGE // "OOM kill event"' <<<"$line")

    if [[ "$id" == d989611b15e44c9dbf31e3c81256e4ed ]]; then
        source="systemd-oomd, memory pressure"
    else
        source="kernel OOM killer, last resort"
    fi

    notify-send -u critical -a "OOM Killer" "Killed: $unit" "$msg ($source)"
done
