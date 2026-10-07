#!/usr/bin/env bash

profile_has homelab || exit 0

mkdir -p "${HOME}/sync"

STATE="${HOME}/.local/state/syncthing"
# per-host device identity
SECRET_DIR="$DOTFILES/secrets/syncthing/$(hostname)"
API_WAIT_SECONDS=30

paired=false
if secret_is_plaintext "${SECRET_DIR}/config.xml" && secret_is_plaintext "${SECRET_DIR}/key.pem"; then
    # only a new or changed identity is installed, a matching one keeps its live config and transfers
    if ! cmp -s "${SECRET_DIR}/cert.pem" "${STATE}/cert.pem" || ! cmp -s "${SECRET_DIR}/key.pem" "${STATE}/key.pem" || [[ ! -f "${STATE}/config.xml" ]]; then
        # install before the daemon starts so it comes up paired
        systemctl --user stop syncthing.service
        mkdir -p "${STATE}"
        install -m 600 "${SECRET_DIR}/config.xml" "${STATE}/config.xml"
        install -m 644 "${SECRET_DIR}/cert.pem" "${STATE}/cert.pem"
        install -m 600 "${SECRET_DIR}/key.pem" "${STATE}/key.pem"
    fi
    paired=true
fi

systemctl --user enable --now syncthing.service
for _ in $(seq 1 "$API_WAIT_SECONDS"); do
    if syncthing cli show system >/dev/null 2>&1; then break; fi
    sleep 1
done
syncthing cli show system >/dev/null 2>&1 || exit 0

# the only peer is static: no discovery, relays or port mapping
for option in local-ann-enabled global-ann-enabled relays-enabled natenabled; do
    syncthing cli config options "$option" set false
done

# no secrets: fresh identity, pair manually in the ui
$paired && exit 0
if ! syncthing cli config folders list 2>/dev/null | grep -qx sync; then
    syncthing cli config folders add-json \
        "{\"id\":\"sync\",\"label\":\"sync\",\"path\":\"${HOME}/sync\",\"type\":\"sendreceive\",\"fsWatcherEnabled\":true,\"ignorePerms\":true}"
fi
