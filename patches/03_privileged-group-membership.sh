#!/usr/bin/env bash
# drop docker, libvirt and i2c membership: docker and libvirt hand any user process root, i2c raw smbus writes; sudo and ddcutil's uaccess rule replace them
# and narrow rustnet's capture caps to the wireshark group now, as its hook only does on the next upgrade
set -euo pipefail

for group in docker libvirt i2c; do
    id -nG "$USER" | tr ' ' '\n' | grep -qx "$group" || continue
    sudo gpasswd -d "$USER" "$group"
done

if [[ -n "$(getcap /usr/bin/rustnet 2>/dev/null)" && "$(stat -c %G /usr/bin/rustnet)" != wireshark ]]; then
    if getent group wireshark >/dev/null; then
        sudo chgrp wireshark /usr/bin/rustnet
        sudo chmod 750 /usr/bin/rustnet
        sudo setcap cap_net_raw,cap_bpf,cap_perfmon+ep /usr/bin/rustnet
    else
        sudo setcap -r /usr/bin/rustnet
    fi
fi
