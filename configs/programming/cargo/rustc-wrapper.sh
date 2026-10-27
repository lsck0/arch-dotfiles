#!/bin/sh
# sccache fails every compile when its redis is down: fall back to plain rustc then
host=@HOST@
port=@PORT@
if nc -z -w 1 "$host" "$port" 2> /dev/null; then exec sccache "$@"; fi
exec "$@"
