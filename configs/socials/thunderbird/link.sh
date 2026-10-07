#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

command -v thunderbird >/dev/null 2>&1 || exit 0

# newer builds follow xdg like firefox, older ones keep ~/.thunderbird
profiles_root() {
    local root
    for root in "${HOME}/.config/mozilla/thunderbird" "${HOME}/.thunderbird"; do
        [[ -f "${root}/profiles.ini" ]] && echo "$root" && return
    done
}

# no profile until first run; a headless run creates one
if [[ -z "$(profiles_root)" ]]; then
    # timeout ends the run on purpose, the profile check below is the real result
    timeout 20 thunderbird --headless >/dev/null 2>&1 || true
fi
root=$(profiles_root)
[[ -n "$root" ]] || exit 0

set -e

colors="${HOME}/.cache/wal/colors-thunderbird.css"
while read -r profile; do
    [[ -n "$profile" ]] || continue
    dir="${root}/${profile}"
    [[ -d "$dir" ]] || continue
    mkdir -p "${dir}/chrome"
    ln -sfn "${PWD}/userChrome.css" "${dir}/chrome/userChrome.css"
    ln -sfn "$colors" "${dir}/chrome/colors.css"
    ln -sfn "${PWD}/user.js" "${dir}/user.js"
done < <(sed -n 's/^Path=//p' "${root}/profiles.ini")
