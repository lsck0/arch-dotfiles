#!/usr/bin/env bash


if ! command -v discord >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p ${HOME}/.config/discord
mkdir -p ${HOME}/.config/BetterDiscord/plugins
mkdir -p ${HOME}/.config/BetterDiscord/themes

ln -sf ${PWD}/discord_settings.json ${HOME}/.config/discord/settings.json

# copy instead if link otherwise betterdiscord cannot see file changes
#ln -sf ${PWD}/wal.theme.css ${HOME}/.config/BetterDiscord/themes/
cp ${PWD}/wal.theme.css ${HOME}/.config/BetterDiscord/themes/wal.theme.css

# download plugins
wget "https://github.com/JustOptimize/ShowHiddenChannels/releases/download/v0.6.8/ShowHiddenChannels.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/ShowHiddenChannels.plugin.js
wget "https://raw.githubusercontent.com/1Lighty/BetterDiscordPlugins/refs/heads/master/Plugins/MessageLoggerV2/MessageLoggerV2.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/MessageLoggerV2.plugin.js
wget "https://raw.githubusercontent.com/Farcrada/DiscordPlugins/7f1c3f98461bcf1b336c2df6e28ca025d09d03cb/Double-click-to-edit/DoubleClickToEdit.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/DoubleClickToEdit.plugin.js
wget "https://raw.githubusercontent.com/TheLazySquid/BetterDiscordPlugins/d4ff127db89318d2361086e0e85251fcc72e4fed/plugins/ZipPreview/ZipPreview.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/ZipPreview.plugin.js
wget "https://raw.githubusercontent.com/mwittrien/BetterDiscordAddons/50d8a379b9e98e114a3e4f20871ae1aaea13ab8d/Plugins/LastMessageDate/LastMessageDate.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/LastMessageDate.plugin.js
wget "https://raw.githubusercontent.com/zerebos/BetterDiscordAddons/6d839d0ab65371819b081218bc43b09d7d6e762d/Plugins/DoNotTrack/DoNotTrack.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/DoNotTrack.plugin.js
