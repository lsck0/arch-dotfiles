#!/bin/sh
# sccache fails every compile when its redis is down: fall back to plain rustc then.
# The reachability probe is cached for a few seconds, so a build does not pay it once per crate.
host=@HOST@
port=@PORT@
cache="${XDG_RUNTIME_DIR:-/tmp}/sccache-probe-$host-$port"
cache_ttl_s=10

up=
if [ -f "$cache" ]; then
    age_s=$(($(date +%s) - $(stat -c %Y "$cache" 2> /dev/null || echo 0)))
    if [ "$age_s" -ge 0 ] && [ "$age_s" -lt "$cache_ttl_s" ]; then up=$(cat "$cache"); fi
fi
if [ -z "$up" ]; then
    if nc -z -w 1 "$host" "$port" 2> /dev/null; then up=yes; else up=no; fi
    printf '%s' "$up" > "$cache"
fi
if [ "$up" = yes ]; then exec sccache "$@"; fi
exec "$@"
