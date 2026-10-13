#!/usr/bin/env bash

command -v hyprpm >/dev/null 2>&1 || exit 0

# hyprpm guards its store as root, so add/update/enable sudo every call until it exists. at login (uwsm, no tty) the
# FIDO2 sudo prompt cannot be answered and the attempt only lights the fingerprint reader, so mutate the store only with
# a terminal (system-update, or this script by hand). reloading an already-built store is a user-read, safe at login.
STORE=/var/cache/hyprpm
REPOS=(
    "https://github.com/virtcode/hypr-dynamic-cursors|dynamic-cursors"
)

if [[ ! -t 1 ]]; then
    # login: load the prebuilt plugin without ever sudo'ing; nothing built yet means nothing to load
    [[ -d "$STORE" ]] || exit 0
    hyprctl plugin list 2>/dev/null | grep -qi dynamic-cursors || hyprpm reload
    exit 0
fi

set -x
exec > >(tee -a "$HOME/.local/state/hypr-manual-link.log") 2>&1

# headers first: `hyprpm add` refuses to build without them; every hyprland update rebuilds each added repo
STATE="$HOME/.local/state/hypr-plugins-built-for"
commit=$(hyprctl version -j 2>/dev/null | jq -r '.commit // empty')
changed=0
if [[ -z "$commit" || "$(cat "$STATE" 2>/dev/null)" != "$commit" ]]; then
    if hyprpm update -f < <(yes); then
        mkdir -p "$(dirname "$STATE")"
        printf '%s\n' "$commit" > "$STATE"
        changed=1
    fi
fi

listed=$(hyprpm list 2>/dev/null)
for entry in "${REPOS[@]}"; do
    url="${entry%%|*}"; name="${entry##*|}"
    grep -qiF "Repository $name " <<<"$listed" && continue
    yes | hyprpm add "$url" || true
    changed=1
done

if [[ "$changed" == 1 ]] || ! hyprctl plugin list 2>/dev/null | grep -qi dynamic-cursors; then
    hyprpm enable dynamic-cursors || true
    hyprpm reload
fi
