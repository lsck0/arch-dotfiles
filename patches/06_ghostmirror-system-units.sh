#!/usr/bin/env bash
# drop the ghostmirror user units: root ranks the mirrorlist now (configs/base/ghostmirror system units), the user can no longer write it

set -euo pipefail

UNIT_DIR="${HOME}/.config/systemd/user"

[[ -e "$UNIT_DIR/ghostmirror.timer" || -e "$UNIT_DIR/ghostmirror-refresh.timer" ]] || exit 0
systemctl --user disable --now ghostmirror.timer ghostmirror-refresh.timer
rm -f "$UNIT_DIR"/ghostmirror{,-refresh}.{service,timer}
systemctl --user daemon-reload
