#!/usr/bin/env bash

if [[ ! -d ${HOME}/.config/mozilla/firefox ]]; then
    exit 0
fi

set -ex

# fix pywalfox not seeing configs
ln -sfn ${HOME}/.config/mozilla/firefox ${HOME}/.config/firefox

# Transparent app shell + the pref that makes userChrome.css load at all.
# Every profile in profiles.ini gets them, not a hardcoded directory: the
# profile name is randomly generated per install (jvx2k0g9.default-release
# here), so a fresh machine would never match a pinned path.
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
