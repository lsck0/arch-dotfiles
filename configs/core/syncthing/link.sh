#!/usr/bin/env bash

profile_has homelab || exit 0

mkdir -p "${HOME}/sync"
# the identity module drops a per-repo per-machine .identity/ (browser profiles, agent state, aws/gnupg/ssh/kube
# creds, caches) into repos kept under ~/sync; keep those machine-local, never replicate them to the nas
printf '%s\n' '**/.identity' >"${HOME}/sync/.stignore"

STATE="${HOME}/.local/state/syncthing"
# per-host device identity
SECRET_DIR="$DOTFILES/secrets/syncthing/$(uname -n)"
GUI_SECRET="$DOTFILES/secrets/syncthing-gui-password"
GUI_GENERATED="${STATE}/gui-password"
NAS_NAME=vm-104-nas
# borg's repo folder (configs/core/borg/borg-backup.sh has the same path and id)
BORG_FOLDER="${XDG_DATA_HOME:-$HOME/.local/share}/borg-repo"
BORG_ID="borg-$(uname -n)"
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

# a background job, not an app: lowest cpu weight and priority
dropin_install syncthing.service 10-background.conf && systemctl --user try-restart syncthing.service
systemctl --user enable --now syncthing.service
for _ in $(seq 1 "$API_WAIT_SECONDS"); do
    if syncthing cli show system >/dev/null 2>&1; then break; fi
    sleep 1
done
# everything below is what keeps the device private, so a daemon that never answers is a failure
syncthing cli show system >/dev/null 2>&1 || { echo "syncthing: the api did not answer in ${API_WAIT_SECONDS}s, settings not applied" >&2; exit 1; }

# set here, whatever config.xml the secrets carry: the only peer is static, so no discovery, relays or port mapping,
# and nothing phones home
for option in local-ann-enabled global-ann-enabled relays-enabled natenabled crenabled; do
    syncthing cli config options "$option" set false
done
syncthing cli config options uraccepted set -- -1

# any local login could open the gui on 127.0.0.1 and read the api key from it; the password is set over stdin, never argv
if secret_is_plaintext "$GUI_SECRET"; then
    password=$(<"$GUI_SECRET")
else
    if [[ ! -s "$GUI_GENERATED" ]]; then
        (umask 077 && head -c 24 /dev/urandom | base64 >"$GUI_GENERATED")
        echo "syncthing: no secrets/syncthing-gui-password, generated the gui password into $GUI_GENERATED" >&2
    fi
    password=$(<"$GUI_GENERATED")
fi
# `syncthing cli -` splits its lines on blanks
[[ "$password" =~ ^[A-Za-z0-9+/=._~-]+$ ]] || { echo "syncthing: the gui password may only hold base64 characters" >&2; exit 1; }
printf 'config gui user set %s\nconfig gui password set %s\n' "$(id -un)" "$password" | syncthing cli - >/dev/null

# no secrets: fresh identity, pair manually in the ui
if ! $paired && ! syncthing cli config folders list 2>/dev/null | grep -qx sync; then
    syncthing cli config folders add-json \
        "{\"id\":\"sync\",\"label\":\"sync\",\"path\":\"${HOME}/sync\",\"type\":\"sendreceive\",\"fsWatcherEnabled\":true,\"ignorePerms\":true}"
fi
# a delete or overwrite from another device keeps the old copy in .stversions for 30 days
if syncthing cli config folders list | grep -qx sync; then
    syncthing cli config folders sync versioning type set staggered
    syncthing cli config folders sync versioning params set maxAge 2592000
fi

# borg's repo, sent to the NAS only. no versioning (a versioned repo keeps every replaced segment twice) and no watcher:
# borg-backup pauses the folder while it writes and the unpause rescans it
mkdir -p "$BORG_FOLDER"
printf '%s\n' lock.exclusive lock.roster >"$BORG_FOLDER/.stignore"
nas=""
for device in $(syncthing cli config devices list); do
    if [[ "$(syncthing cli config devices "$device" name get)" == "$NAS_NAME" ]]; then nas=$device; fi
done
if ! syncthing cli config folders list | grep -qx "$BORG_ID"; then
    if [[ -z "$nas" ]]; then
        echo "syncthing: no device $NAS_NAME yet, $BORG_ID not shared; borg backs up locally until it is" >&2
        exit 0
    fi
    me=$(syncthing cli show system | jq -r .myID)
    syncthing cli config folders add-json \
        "{\"id\":\"$BORG_ID\",\"label\":\"$BORG_ID\",\"path\":\"$BORG_FOLDER\",\"type\":\"sendonly\",\"fsWatcherEnabled\":false,\"devices\":[{\"deviceID\":\"$me\"},{\"deviceID\":\"$nas\"}]}"
    echo "syncthing: shared $BORG_ID with $NAS_NAME, accept it there as receive-only without versioning" >&2
fi
syncthing cli config folders "$BORG_ID" type set sendonly
syncthing cli config folders "$BORG_ID" fswatcher-enabled set false
syncthing cli config folders "$BORG_ID" versioning type set ''
