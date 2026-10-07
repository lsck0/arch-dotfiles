#!/usr/bin/env bash

# a system unit: unit_present here would look in the user scope
[[ -e /usr/lib/systemd/system/systemd-oomd.service ]] || exit 0
mkdir -p "${UNIT_DIR}/app.slice.d"
ln -sfn "${PWD}/oomd-app.slice.conf" "${UNIT_DIR}/app.slice.d/10-oomd.conf"
unit_install oom-notify.service
systemctl --user enable --now oom-notify.service
