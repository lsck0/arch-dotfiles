#!/usr/bin/env bash
# drop docker, libvirt and i2c membership: docker and libvirt hand any user process root, i2c raw smbus writes; sudo and ddcutil's uaccess rule replace them
# and narrow rustnet's capture caps to the wireshark group now, as its hook only does on the next upgrade
set -euo pipefail

# every member, the machine's patch no longer knows which login an older config added
for group in docker libvirt i2c; do
    members=$(getent group "$group" | cut -d: -f4)
    IFS=, read -ra users <<<"$members"
    for user in "${users[@]}"; do gpasswd -d "$user" "$group" >/dev/null; done
done

if [[ -n "$(getcap /usr/bin/rustnet 2>/dev/null)" && "$(stat -c %G /usr/bin/rustnet)" != wireshark ]]; then
    if getent group wireshark >/dev/null; then
        chgrp wireshark /usr/bin/rustnet
        chmod 750 /usr/bin/rustnet
        setcap cap_net_raw,cap_bpf,cap_perfmon+ep /usr/bin/rustnet
    else
        setcap -r /usr/bin/rustnet
    fi
fi
