#!/usr/bin/env bash

# a system unit: unit_present here would look in the user scope
[[ -e /usr/lib/systemd/system/systemd-oomd.service ]] || exit 0
link_as "${PWD}/oomd-app.slice.conf" "${UNIT_DIR}/app.slice.d/10-oomd.conf"
# the desktop itself, never an oomd candidate; system.sh protects its ancestors
link_as "${PWD}/session-protect.slice.conf" "${UNIT_DIR}/session.slice.d/10-protect.conf"
unit_install oom-notify.service
systemctl --user enable --now oom-notify.service
