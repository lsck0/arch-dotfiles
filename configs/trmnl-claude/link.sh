#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source ../../scripts/lib/platform.sh
source ../../scripts/lib/secrets.sh

# one poster per panel: without a fleet config a second machine would overwrite the desktop's numbers with its own
form_factor=$(platform_form_factor ../..) || exit 1
if [[ "$form_factor" != desktop ]]; then
    # never linked on this machine is the common case
    systemctl --user disable --now trmnl-claude.timer 2>/dev/null || true
    exit 0
fi

# without the UUID the timer would fail every 15 minutes for nothing
if ! secret_is_plaintext ../secrets/trmnl-claude.env; then
    echo "configs/trmnl-claude: no readable ../secrets/trmnl-claude.env, skipping" >&2
    exit 0
fi

set -e

mkdir -p "${HOME}/.config/systemd/user"
ln -sfn "${PWD}/trmnl-claude.service" "${HOME}/.config/systemd/user/trmnl-claude.service"
ln -sfn "${PWD}/trmnl-claude.timer" "${HOME}/.config/systemd/user/trmnl-claude.timer"

systemctl --user daemon-reload
systemctl --user enable --now trmnl-claude.timer
