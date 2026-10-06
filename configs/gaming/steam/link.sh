#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

chmod 755 ./steam-launch.sh
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

ln -sfn "${PWD}/themes/cyberpunk/skin.json" "${theme}/skin.json"
ln -sfn "${PWD}/themes/cyberpunk/shared.css" "${theme}/shared.css"
ln -sfn "${PWD}/themes/cyberpunk/libraryroot.custom.css" "${theme}/libraryroot.custom.css"
ln -sfn "${PWD}/themes/cyberpunk/friends.custom.css" "${theme}/friends.custom.css"
ln -sfn "${PWD}/themes/cyberpunk/bigpicture.custom.css" "${theme}/bigpicture.custom.css"
ln -sfn "${PWD}/themes/cyberpunk/all.custom.css" "${theme}/all.custom.css"
ln -sfn "${PWD}/themes/cyberpunk/webkit.custom.css" "${theme}/webkit.custom.css"

# millennium ignores links out of the theme dir, wallust writes a real file
[ -L "${theme}/colors.css" ] && rm "${theme}/colors.css"

# seed the palette before the first switch
tpl="${PWD}/$DOTFILES/configs/base/wallust/templates/wal/colors-steam.css"
out="${theme}/colors.css"
# a palette rendered before the theme dir existed only needs copying
if [ ! -e "$out" ] && [ -f "${HOME}/.cache/wal/colors-steam.css" ]; then
    cp "${HOME}/.cache/wal/colors-steam.css" "$out"
fi
if [ ! -e "$out" ] && [ -f "$tpl" ] && [ -f "${HOME}/.cache/wal/colors" ] && [ "$(wc -l < "${HOME}/.cache/wal/colors")" -ge 16 ]; then
    mkdir -p "${HOME}/.cache/wal"
    python3 - "$tpl" "${HOME}/.cache/wal/colors" "$out" <<'PY'
import sys
tpl, colors, out = sys.argv[1], sys.argv[2], sys.argv[3]
hexes = [l.strip() for l in open(colors) if l.strip()]
s = open(tpl).read()
for i, h in enumerate(hexes[:16]):
    s = s.replace("{color%d}" % i, h)
s = s.replace("{background}", hexes[0])
s = s.replace("{foreground}", hexes[15] if len(hexes) > 15 else hexes[-1])
s = s.replace("{{", "{").replace("}}", "}")
open(out, "w").write(s)
PY
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
