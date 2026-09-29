#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if [[ ! -d ${HOME}/.config/mozilla/firefox ]]; then
    exit 0
fi

set -ex

# pywalfox looks in ~/.config/firefox
ln -sfn ${HOME}/.config/mozilla/firefox ${HOME}/.config/firefox

PROFILES_INI="${HOME}/.config/mozilla/firefox/profiles.ini"
if [[ -f "$PROFILES_INI" ]]; then
    while read -r profile; do
        [[ -n "$profile" ]] || continue
        dir="${HOME}/.config/mozilla/firefox/${profile}"
        [[ -d "$dir" ]] || continue
        mkdir -p "${dir}/chrome"
        ln -sfn "${PWD}/userChrome.css" "${dir}/chrome/userChrome.css"
        ln -sfn "${PWD}/user.js" "${dir}/user.js"
    done < <(sed -n 's/^Path=//p' "$PROFILES_INI")
fi
