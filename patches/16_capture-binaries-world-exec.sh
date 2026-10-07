#!/usr/bin/env bash
# raw-capture binaries kept their caps at mode 755 until their next upgrade: limit them to the wireshark group, or drop the caps
set -euo pipefail

for bin in /usr/bin/rustnet /usr/bin/netscanner; do
    [[ -x "$bin" ]] && [[ -n "$(getcap "$bin")" ]] || continue
    [[ "$(stat -c %a "$bin")" == 750 ]] && continue
    if getent group wireshark >/dev/null; then
        sudo chgrp wireshark "$bin"
        sudo chmod 750 "$bin"
    else
        sudo setcap -r "$bin"
    fi
done
