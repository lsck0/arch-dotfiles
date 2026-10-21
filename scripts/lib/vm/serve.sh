#!/usr/bin/env bash
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
    "GET /step/"* | "GET /file/"*)
        file="$dir/${path#/}"
        if [[ "$path" != *..* && -f "$file" ]]; then
            reply "200 OK" "$(stat -L -c %s "$file")"
            cat "$file"
        else
            reply "404 Not Found" 0
        fi
        ;;
    "PUT /bootstrap.log" | "PUT /logs.tgz" | "PUT /drill.log")
        head -c "$len" > "$(< "$dir/upload-to")"
        touch "$dir/uploaded"
        reply "204 No Content" 0
        ;;
    *) reply "404 Not Found" 0 ;;
esac
