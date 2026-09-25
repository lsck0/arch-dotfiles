#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v rclone >/dev/null 2>&1; then
    exit 0
fi

set -ex

RCLONE="$(command -v rclone)"
UNIT_DIR="${HOME}/.config/systemd/user"
mkdir -p "${UNIT_DIR}"

# Resolve the rclone path into the mount unit rather than hardcoding /usr/bin.
sed "s|@RCLONE@|${RCLONE}|g" proton-drive.service > "${UNIT_DIR}/proton-drive.service"

# bisync is the opt-in alternative to the mount; install but do not enable it.
chmod 755 "${PWD}/proton-drive-bisync.sh"
install -Dm644 proton-drive-bisync.service "${UNIT_DIR}/proton-drive-bisync.service"
install -Dm644 proton-drive-bisync.timer "${UNIT_DIR}/proton-drive-bisync.timer"

systemctl --user daemon-reload

# Only start the mount once `rclone config` has created the protondrive remote.
if rclone listremotes 2>/dev/null | grep -qx 'protondrive:'; then
    systemctl --user enable --now proton-drive.service
else
    echo "proton-drive: no 'protondrive:' remote yet — run 'rclone config' then 'systemctl --user enable --now proton-drive.service' (see configs/proton/README.md)" >&2
fi
