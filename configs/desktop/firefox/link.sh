#!/usr/bin/env bash

FIREFOX_HOME="${HOME}/.config/mozilla/firefox"
PROFILES_INI="${FIREFOX_HOME}/profiles.ini"

# no profile until first run; a headless run creates default-release.
# timeout ends the run on purpose, the profile check below is the real result
[[ -f "$PROFILES_INI" ]] || timeout 20 firefox --headless about:blank >/dev/null 2>&1 || true
[[ -f "$PROFILES_INI" ]] || exit 0

# pywalfox looks in ~/.config/firefox
link_dir "$FIREFOX_HOME" "${HOME}/.config/firefox"

while read -r profile; do
    dir="${FIREFOX_HOME}/${profile}"
    [[ -n "$profile" && -d "$dir" ]] || continue
    link_into "${dir}/chrome" userChrome.css
    file_render user.js "${dir}/user.js" HOME="$HOME"
done < <(sed -n 's/^Path=//p' "$PROFILES_INI")
