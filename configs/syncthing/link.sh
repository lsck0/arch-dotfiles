#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source ../../scripts/lib/personal.sh
is_personal || exit 0

source ../../scripts/lib/secrets.sh

if ! command -v syncthing >/dev/null 2>&1; then
    exit 0
fi

set -e

mkdir -p "${HOME}/sync"

STATE="${HOME}/.local/state/syncthing"
# per-host device identity
SECRET_DIR="../secrets/syncthing/$(hostname)"

if secret_is_plaintext "${SECRET_DIR}/config.xml" && secret_is_plaintext "${SECRET_DIR}/key.pem"; then
    # install before the daemon starts so it comes up paired
    systemctl --user stop syncthing.service
    mkdir -p "${STATE}"
    install -m 600 "${SECRET_DIR}/config.xml" "${STATE}/config.xml"
    install -m 644 "${SECRET_DIR}/cert.pem" "${STATE}/cert.pem"
    install -m 600 "${SECRET_DIR}/key.pem" "${STATE}/key.pem"
    systemctl --user enable --now syncthing.service
    exit 0
fi

# no secrets: fresh identity, pair manually in the ui
systemctl --user enable --now syncthing.service
for _ in $(seq 1 30); do
    if syncthing cli show system >/dev/null 2>&1; then break; fi
    sleep 1
done
if syncthing cli show system >/dev/null 2>&1 \
    && ! syncthing cli config folders list 2>/dev/null | grep -qx sync; then
    syncthing cli config folders add-json \
        "{\"id\":\"sync\",\"label\":\"sync\",\"path\":\"${HOME}/sync\",\"type\":\"sendreceive\",\"fsWatcherEnabled\":true,\"ignorePerms\":true}"
fi
