#!/usr/bin/env bash
# every driverless printer (IPP Everywhere, AirPrint) cups finds over mdns gets a permanent queue, bound to its .local
# service name so a new dhcp lease never breaks it; a printer that has a queue is left alone. root, from
# configs/hardware/printing/system.sh and printers-sync.service (a home connect, NM dispatcher 95-printers-sync)
set -uo pipefail

# the dnssd backend browses this long; mdns answers come within a second or two
DISCOVERY_TIMEOUT_S=10
# an AirPrint printer advertises both: one queue, on plain ipp
SERVICES=(ipp ipps)

discovered=$(lpinfo --timeout "$DISCOVERY_TIMEOUT_S" --include-schemes dnssd -v 2>/dev/null) || true
existing=$(lpstat -v 2>/dev/null) || true
status=0
seen=" "
created=""
for svc in "${SERVICES[@]}"; do
    while read -r _ uri; do
        # the service's mdns name only, never an address
        [[ "$uri" =~ ^dnssd://([^/?]+)\._${svc}\._tcp\.local/(\?uuid=([0-9A-Za-z-]+))?$ ]] || continue
        instance=${BASH_REMATCH[1]}
        key=${BASH_REMATCH[3]:-$instance}
        [[ "$seen" != *" $key "* ]] || continue
        seen+="$key "
        # a queue for this printer already exists, under whatever name and service
        [[ "$existing" != *"$key"* ]] || continue
        # "HP%20ENVY%205640%20series%20%5BB8A730%5D" -> HP_ENVY_5640_series_B8A730
        name=$(printf '%b' "${instance//%/\\x}" | sed -E 's/[^A-Za-z0-9_-]+/_/g; s/^_+//; s/_+$//')
        [[ -n "$name" ]] || continue
        if lpstat -p "$name" >/dev/null 2>&1; then
            echo "printers-sync: a queue named $name exists for another device, not adding $uri" >&2
            continue
        fi
        if lpadmin -p "$name" -E -v "$uri" -m everywhere -o printer-is-shared=false; then
            echo "printers-sync: added $name ($uri)" >&2
            created=${created:-$name}
        else
            echo "printers-sync: $uri does not take an IPP Everywhere queue" >&2
            status=1
        fi
    done <<<"$discovered"
done

# only where none is set: a chosen default stays
if [[ -n "$created" ]] && ! lpstat -d 2>/dev/null | grep -q 'system default destination:'; then
    lpadmin -d "$created" || status=1
fi
exit "$status"
