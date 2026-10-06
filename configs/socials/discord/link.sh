#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

bd="${HOME}/.config/BetterDiscord"
mkdir -p "${HOME}/.config/discord" "${bd}/plugins" "${bd}/themes"

ln -sfn "${PWD}/discord_settings.json" "${HOME}/.config/discord/settings.json"

# copy, betterdiscord misses changes through a symlink
cp "${PWD}/wal.theme.css" "${bd}/themes/wal.theme.css"
cp "${PWD}/plugins/QuickshellVoiceStatus.plugin.js" "${bd}/plugins/QuickshellVoiceStatus.plugin.js"

# pinned to commit shas
for url in \
    "https://raw.githubusercontent.com/mwittrien/BetterDiscordAddons/21c049bb77fbe3ffc5cda8961830c098fc6bccad/Library/0BDFDB.plugin.js" \
    "https://raw.githubusercontent.com/mwittrien/BetterDiscordAddons/21c049bb77fbe3ffc5cda8961830c098fc6bccad/Plugins/LastMessageDate/LastMessageDate.plugin.js" \
    "https://raw.githubusercontent.com/Farcrada/DiscordPlugins/7f1c3f98461bcf1b336c2df6e28ca025d09d03cb/Double-click-to-edit/DoubleClickToEdit.plugin.js" \
    "https://raw.githubusercontent.com/TheLazySquid/BetterDiscordPlugins/3ce443c86a14185b2b2d088e9be49b8245d17c6c/plugins/ZipPreview/ZipPreview.plugin.js" \
    "https://raw.githubusercontent.com/zerebos/BetterDiscordAddons/6d839d0ab65371819b081218bc43b09d7d6e762d/Plugins/DoNotTrack/DoNotTrack.plugin.js"; do
    wget "$url" -O "${bd}/plugins/${url##*/}"
done

source ../../../scripts/lib/user-hook.sh
user_hook_install ./hook betterdiscord-inject
