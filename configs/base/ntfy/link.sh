#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source $DOTFILES/scripts/lib/personal.sh
source $DOTFILES/scripts/lib/secrets.sh
is_personal || exit 0

command -v notify-send >/dev/null 2>&1 || exit 0

# homelab ntfy denies anonymous reads
if ! secret_is_plaintext $DOTFILES/secrets/ntfy-desktop-token; then
    echo "configs/base/ntfy: no readable $DOTFILES/secrets/ntfy-desktop-token, skipping" >&2
    # never enabled without the token is the common case
    systemctl --user disable --now ntfy-notify.service >/dev/null 2>&1 || true
    exit 0
fi

set -e

# topics come from the homelab checkout; configs/programming/projects clones it too but runs after us (sorted order)
HOMELAB="${HOME}/projects/homelab"
if [[ ! -d "${HOMELAB}/.git" ]]; then
    mkdir -p "${HOME}/projects"
    GIT_TERMINAL_PROMPT=0 git clone --recurse-submodules \
        https://github.com/lsck0/homelab.git "${HOMELAB}" \
        || { echo "ntfy: cloning homelab failed, skipping" >&2; exit 0; }
fi

chmod 755 "${PWD}/ntfy-notify.py"
install -Dm644 "${PWD}/ntfy-notify.service" "${HOME}/.config/systemd/user/ntfy-notify.service"
systemctl --user daemon-reload
systemctl --user enable --now ntfy-notify.service
