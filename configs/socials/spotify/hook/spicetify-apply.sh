#!/usr/bin/env bash
# spicetify apply once spotify is logged in and the user's copy is unpatched (first login, or an upgrade replaced it);
# permanent, a patched copy is a no-op. /opt/spotify stays root's: a client every user runs is never writable by one

set -euo pipefail

PREFS="${HOME}/.config/spotify/prefs"
SPOTIFY_SYSTEM=/opt/spotify
SPOTIFY_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/spotify-patched"
APPS="${SPOTIFY_DIR}/Apps"
STAMP="${SPOTIFY_DIR}/.dotfiles-source"
PACMAN_LOCK=/var/lib/pacman/db.lck
PACMAN_WAIT_SECONDS=300

grep -q '^autologin.username' "$PREFS" 2>/dev/null || exit 0

# the xpui.spa trigger fires mid-transaction: wait for pacman to finish
for ((waited = 0; waited < PACMAN_WAIT_SECONDS; waited++)); do
    [[ -e "$PACMAN_LOCK" ]] || break
    sleep 1
done
if [[ -e "$PACMAN_LOCK" ]]; then
    echo "spicetify-apply: pacman still busy after ${PACMAN_WAIT_SECONDS}s" >&2
    exit 1
fi

# the path unit, the login and link.sh can fire together
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/spicetify-apply.lock"
flock 9

# a fresh copy per installed client: reflinked on btrfs, a plain copy elsewhere
source=$(pacman -Q spotify)
source+=" $(stat -c %Y "${SPOTIFY_SYSTEM}/Apps/xpui.spa" 2>/dev/null || true)"
if [[ "$(cat "$STAMP" 2>/dev/null)" != "$source" ]]; then
    rm -rf "$SPOTIFY_DIR"
    mkdir -p "${SPOTIFY_DIR%/*}"
    cp -a --reflink=auto "$SPOTIFY_SYSTEM" "$SPOTIFY_DIR"
    chmod -R u+w "$SPOTIFY_DIR"
    echo "$source" >"$STAMP"
fi
spicetify config spotify_path "$SPOTIFY_DIR" >/dev/null
[[ -e "${APPS}/xpui.spa" || ! -d "${APPS}/xpui" ]] || exit 0

# a fresh copy no longer matches the backup, so apply fails and a fresh backup is taken
spicetify apply || spicetify backup apply
spicetify enable-devtools
python3 "$(dirname "$(readlink -f "$0")")/../spicetify-unmap-classes.py" "${APPS}/xpui"
