#!/usr/bin/env bash

THEME="${HOME}/.local/share/Steam/millennium/themes/cyberpunk"
PALETTE="${HOME}/.cache/wal/colors-steam.css"
MILLENNIUM_CONFIG="${HOME}/.config/millennium/config.json"

# route the launcher entry through the wrapper so every game gets gamemode, mangohud and obs capture;
# sed replacement metacharacters in the repo path (\ & #) escaped
launcher=${PWD//\\/\\\\}; launcher=${launcher//&/\\&}; launcher=${launcher//#/\\#}
desktop_override steam.desktop "s#/usr/bin/steam#${launcher}/steam-launch.sh#g"

link_into "$THEME" themes/cyberpunk/*

# millennium ignores links out of the theme dir, wallust writes a real file
[[ ! -L "${THEME}/colors.css" ]] || rm "${THEME}/colors.css"

# a palette rendered before the theme dir existed only needs copying
if [[ ! -e "${THEME}/colors.css" && -f "$PALETTE" ]]; then
    cp "$PALETTE" "${THEME}/colors.css"
fi

# steam overwrites this on exit, close it first
if [[ -f "$MILLENNIUM_CONFIG" ]]; then
    json_update "$MILLENNIUM_CONFIG" '.themes.activeTheme = "cyberpunk"'
fi

millennium_linked() { [[ "$(readlink "${HOME}/.local/share/Steam/ubuntu12_32/libXtst.so.6")" == /usr/lib/millennium/* ]]; }
user_hook_oneshot ./hook millennium-link millennium_linked
