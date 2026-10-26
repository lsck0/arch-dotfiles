#!/usr/bin/env bash
# One request per socat fork: beacons append to $dir/beacons, uploads land in $dir/upload.
set -euo pipefail
dir=$1
read -r method path _
len=0
while IFS= read -r line && [[ -n "${line%$'\r'}" ]]; do
    if [[ "${line,,}" == content-length:* ]]; then len=$(tr -dc 0-9 <<< "${line#*:}"); fi
done
reply() { printf 'HTTP/1.0 %s\r\nContent-Length: %s\r\n\r\n' "$1" "$2"; }
case "$method $path" in
    "GET /beacon/"*)
        echo "${path#/beacon/}" >> "$dir/beacons"
        reply "204 No Content" 0
        ;;
    "PUT /bootstrap.log" | "PUT /logs.tgz")
        head -c "$len" > "$dir/upload/${path#/}"
        reply "204 No Content" 0
        ;;
    *) reply "404 Not Found" 0 ;;
esac
