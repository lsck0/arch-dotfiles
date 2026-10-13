#!/usr/bin/env bash

command -v thunderbird >/dev/null 2>&1 || exit 0

# a fresh home gets ~/.config/thunderbird (156 on), older homes keep ~/.thunderbird
profiles_root() {
    local root
    for root in "${XDG_CONFIG_HOME:-$HOME/.config}/thunderbird" "${HOME}/.config/mozilla/thunderbird" \
        "${HOME}/.thunderbird"; do
        [[ -f "${root}/profiles.ini" ]] && echo "$root" && return
    done
}

# no profile until first run; a headless run creates one
if [[ -z "$(profiles_root)" ]]; then
    # timeout ends the run on purpose, the profile check below is the real result
    timeout 20 thunderbird --headless >/dev/null 2>&1 || true
fi
# none yet is the empty string, not a failure
root=$(profiles_root) || true
[[ -n "$root" ]] || exit 0

colors="${HOME}/.cache/wal/colors-thunderbird.css"
while read -r profile; do
    [[ -n "$profile" ]] || continue
    dir="${root}/${profile}"
    [[ -d "$dir" ]] || continue
    mkdir -p "${dir}/chrome"
    # link_as: a profile's own userChrome.css or user.js is preserved, never replaced
    link_as "${PWD}/userChrome.css" "${dir}/chrome/userChrome.css"
    link_as "$colors" "${dir}/chrome/colors.css"
    link_as "${PWD}/user.js" "${dir}/user.js"
done < <(sed -n 's/^Path=//p' "${root}/profiles.ini")
