#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v syncthing >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p "${HOME}/sync"

STATE="${HOME}/.local/state/syncthing"
# Per-host identity, mirroring the per-platform wg configs. cert.pem + key.pem are
# the device ID; config.xml names the paired devices and the folder.
SECRET_DIR="../secrets/syncthing/$(hostname)"

if [ -f "${SECRET_DIR}/config.xml" ] && [ -f "${SECRET_DIR}/key.pem" ]; then
    # Reproduce the authed device from secrets: install before the daemon starts,
    # so it comes up already paired. The database and GUI TLS cert regenerate.
    systemctl --user stop syncthing.service 2>/dev/null || true
    mkdir -p "${STATE}"
    install -m 600 "${SECRET_DIR}/config.xml" "${STATE}/config.xml"
    install -m 644 "${SECRET_DIR}/cert.pem" "${STATE}/cert.pem"
    install -m 600 "${SECRET_DIR}/key.pem" "${STATE}/key.pem"
    systemctl --user enable --now syncthing.service
    exit 0
fi

# No secrets for this host: fresh identity, folder created via the API, device
# pairing done manually in the UI (http://127.0.0.1:8384).
systemctl --user enable --now syncthing.service || true
for _ in $(seq 1 30); do
    if syncthing cli show system >/dev/null 2>&1; then break; fi
    sleep 1
done
if syncthing cli show system >/dev/null 2>&1 \
    && ! syncthing cli config folders list 2>/dev/null | grep -qx sync; then
    syncthing cli config folders add-json \
        "{\"id\":\"sync\",\"label\":\"sync\",\"path\":\"${HOME}/sync\",\"type\":\"sendreceive\",\"fsWatcherEnabled\":true,\"ignorePerms\":true}"
fi
