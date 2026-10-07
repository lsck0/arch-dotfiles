#!/usr/bin/env bash

TOKEN="$DOTFILES/secrets/ntfy-desktop-token"
HOMELAB_REPO="${HOME}/projects/homelab"

# homelab ntfy denies anonymous reads: no homelab user, notifier or token, no forwarder
if ! profile_has homelab || ! command -v notify-send >/dev/null 2>&1 || ! secret_is_plaintext "$TOKEN"; then
    if profile_has homelab && ! secret_is_plaintext "$TOKEN"; then
        echo "configs/base/ntfy: no readable $TOKEN, skipping" >&2
    fi
    systemctl --user disable --now ntfy-notify.service >/dev/null 2>&1 || true
    exit 0
fi

# topics come from the homelab checkout; configs/programming/projects clones it too but runs after us (sorted order)
if [[ ! -d "${HOMELAB_REPO}/.git" ]]; then
    mkdir -p "${HOME}/projects"
    GIT_TERMINAL_PROMPT=0 git clone --recurse-submodules \
        https://github.com/lsck0/homelab.git "${HOMELAB_REPO}" \
        || { echo "ntfy: cloning homelab failed, skipping" >&2; exit 0; }
fi

unit_install ntfy-notify.service
systemctl --user enable --now ntfy-notify.service
