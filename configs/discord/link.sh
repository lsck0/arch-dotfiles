#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1


if ! command -v discord >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p ${HOME}/.config/discord
mkdir -p ${HOME}/.config/BetterDiscord/plugins
mkdir -p ${HOME}/.config/BetterDiscord/themes

ln -sfn ${PWD}/discord_settings.json ${HOME}/.config/discord/settings.json

# copy instead if link otherwise betterdiscord cannot see file changes ln -sf ${PWD}/wal.theme.css ${HOME}/.config/BetterDiscord/themes/
cp ${PWD}/wal.theme.css ${HOME}/.config/BetterDiscord/themes/wal.theme.css

mkdir -p ${HOME}/.config/BetterDiscord/plugins

# my plugins
cp ${PWD}/plugins/QuickshellVoiceStatus.plugin.js ${HOME}/.config/BetterDiscord/plugins/QuickshellVoiceStatus.plugin.js

# download plugins (all pinned to a commit SHA, no moving refs)
wget "https://raw.githubusercontent.com/mwittrien/BetterDiscordAddons/21c049bb77fbe3ffc5cda8961830c098fc6bccad/Library/0BDFDB.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/0BDFDB.plugin.js
wget "https://raw.githubusercontent.com/mwittrien/BetterDiscordAddons/21c049bb77fbe3ffc5cda8961830c098fc6bccad/Plugins/LastMessageDate/LastMessageDate.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/LastMessageDate.plugin.js
wget "https://raw.githubusercontent.com/Farcrada/DiscordPlugins/7f1c3f98461bcf1b336c2df6e28ca025d09d03cb/Double-click-to-edit/DoubleClickToEdit.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/DoubleClickToEdit.plugin.js
wget "https://raw.githubusercontent.com/TheLazySquid/BetterDiscordPlugins/3ce443c86a14185b2b2d088e9be49b8245d17c6c/plugins/ZipPreview/ZipPreview.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/ZipPreview.plugin.js
wget "https://raw.githubusercontent.com/zerebos/BetterDiscordAddons/6d839d0ab65371819b081218bc43b09d7d6e762d/Plugins/DoNotTrack/DoNotTrack.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/DoNotTrack.plugin.js
