#!/usr/bin/env bash
# capgemini [url...]: the work sites in their own chromium profile, away from the personal cookie jar and firefox's
# script blockers; without a url it opens just the ARC portal (teams/outlook are .desktop actions). the managed policy (configs/desktop/chromium)
# lets only the microsoft 365 and ping sign-in use third-party cookies; camera, mic and screen share ask per origin
set -euo pipefail

# entra id and pingfederate treat tor exits as anonymous ips and block or re-prompt the sign-in
if systemctl is-active -q tor-router.service; then
    echo "capgemini: tor-router is on, turn it off first" >&2
    notify-send -u critical Capgemini "tor-router is on, turn it off first" || true
    exit 1
fi

(($#)) || set -- https://arc.capgemini.com/
exec chromium --user-data-dir="${XDG_DATA_HOME:-$HOME/.local/share}/capgemini/chromium" "$@"
