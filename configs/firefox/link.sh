#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v firefox >/dev/null 2>&1; then
    exit 0
fi

# no profile until first run; a headless run creates default-release
if [[ ! -f "${HOME}/.config/mozilla/firefox/profiles.ini" ]]; then
    timeout 20 firefox --headless about:blank >/dev/null 2>&1 || true
fi
if [[ ! -d "${HOME}/.config/mozilla/firefox" ]]; then
    exit 0
fi

set -e

# pywalfox looks in ~/.config/firefox
ln -sfn "${HOME}/.config/mozilla/firefox" "${HOME}/.config/firefox"

PROFILES_INI="${HOME}/.config/mozilla/firefox/profiles.ini"
if [[ -f "$PROFILES_INI" ]]; then
    while read -r profile; do
        [[ -n "$profile" ]] || continue
        dir="${HOME}/.config/mozilla/firefox/${profile}"
        [[ -d "$dir" ]] || continue
        mkdir -p "${dir}/chrome"
        ln -sfn "${PWD}/userChrome.css" "${dir}/chrome/userChrome.css"
        # copy with @HOME@ filled in; rm first so an old link is not written through
        rm -f "${dir}/user.js"
        sed "s|@HOME@|$HOME|" "${PWD}/user.js" > "${dir}/user.js"
    done < <(sed -n 's/^Path=//p' "$PROFILES_INI")
fi
