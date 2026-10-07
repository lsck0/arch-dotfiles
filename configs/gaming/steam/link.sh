#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

# route the launcher entry through the wrapper so every game gets gamemode, mangohud and obs capture
desktop_src=/usr/share/applications/steam.desktop
desktop_dst="${HOME}/.local/share/applications/steam.desktop"
if [ -f "$desktop_src" ]; then
    mkdir -p "$(dirname "$desktop_dst")"
    # escape sed replacement metacharacters in case the repo path holds \ & or #
    repl=${PWD//\\/\\\\}; repl=${repl//&/\\&}; repl=${repl//#/\\#}
    sed "s#/usr/bin/steam#${repl}/steam-launch.sh#g" "$desktop_src" >"$desktop_dst"
fi

skins="${HOME}/.local/share/Steam/millennium/themes"
theme="${skins}/cyberpunk"

mkdir -p "${theme}"

for f in "$PWD"/themes/cyberpunk/*; do ln -sfn "$f" "$theme/${f##*/}"; done

# millennium ignores links out of the theme dir, wallust writes a real file
[ -L "${theme}/colors.css" ] && rm "${theme}/colors.css"

# a palette rendered before the theme dir existed only needs copying
if [ ! -e "${theme}/colors.css" ] && [ -f "${HOME}/.cache/wal/colors-steam.css" ]; then
    cp "${HOME}/.cache/wal/colors-steam.css" "${theme}/colors.css"
fi

# steam overwrites this on exit, close it first
cfg="${HOME}/.config/millennium/config.json"
if [ -f "$cfg" ]; then
    python3 - "$cfg" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d.setdefault("themes", {})["activeTheme"] = "cyberpunk"
json.dump(d, open(p, "w"), indent=2)
PY
fi

millennium_linked() { [[ "$(readlink "${HOME}/.local/share/Steam/ubuntu12_32/libXtst.so.6")" == /usr/lib/millennium/* ]]; }
source $DOTFILES/scripts/lib/user-hook.sh
user_hook_oneshot ./hook millennium-link millennium_linked
