#!/usr/bin/env bash

NAS_LINK="${HOME}/nas"
MOUNT=/mnt/homelab

# the mount itself is the machine's (system.sh); the shortcut only for a homelab user, sidebar bookmark in xdg/link.sh
if profile_has homelab; then
    link_dir "$MOUNT" "$NAS_LINK"
elif [[ "$(readlink "$NAS_LINK")" == "$MOUNT" ]]; then
    rm -f "$NAS_LINK"
fi
