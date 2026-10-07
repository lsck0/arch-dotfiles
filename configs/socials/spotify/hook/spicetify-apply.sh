#!/usr/bin/env bash
# spicetify apply once spotify is logged in and its client is unpatched (first login, or an upgrade replaced it); permanent,
# a patched client is a no-op

set -euo pipefail

PREFS="${HOME}/.config/spotify/prefs"
SPOTIFY_DIR=/opt/spotify
APPS="${SPOTIFY_DIR}/Apps"
PACMAN_LOCK=/var/lib/pacman/db.lck
PACMAN_WAIT_SECONDS=300

grep -q '^autologin.username' "$PREFS" 2>/dev/null || exit 0

# the xpui.spa trigger fires mid-transaction: wait for pacman and spotify-group-write.hook to finish
for ((waited = 0; waited < PACMAN_WAIT_SECONDS; waited++)); do
    [[ -e "$PACMAN_LOCK" ]] || break
    sleep 1
done
if [[ -e "$PACMAN_LOCK" ]]; then
    echo "spicetify-apply: pacman still busy after ${PACMAN_WAIT_SECONDS}s" >&2
    exit 1
fi

[[ -w "$APPS" ]] || exit 0
# every logged-in admin's unit fires on an upgrade: one patches, the others then see a patched client
exec 9<"$SPOTIFY_DIR"
flock 9
[[ -e "${APPS}/xpui.spa" || ! -d "${APPS}/xpui" ]] || exit 0

# an upgraded client no longer matches the backup, so apply fails and a fresh backup is taken
spicetify apply || spicetify backup apply
spicetify enable-devtools
python3 "$(dirname "$(readlink -f "$0")")/../spicetify-unmap-classes.py"
