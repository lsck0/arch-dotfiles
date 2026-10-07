#!/usr/bin/env bash

SECRET="${DOTFILES}/secrets/trmnl-claude.env"

# one poster per panel: without a fleet config a second machine would overwrite the desktop's numbers with its own
if [[ "$FORM_FACTOR" != desktop ]]; then
    # never linked on this machine is the common case
    systemctl --user disable --now trmnl-claude.timer 2>/dev/null || true
    exit 0
fi

# without the UUID the timer would fail every 15 minutes for nothing
if ! secret_is_plaintext "$SECRET"; then
    echo "configs/programming/trmnl-claude: no readable $SECRET, skipping" >&2
    exit 0
fi

unit_install trmnl-claude.service trmnl-claude.timer
systemctl --user enable --now trmnl-claude.timer
