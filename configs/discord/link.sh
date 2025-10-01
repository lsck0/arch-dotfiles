#!/bin/env bash

set -ex

mkdir -p ${HOME}/.config/discord
mkdir -p ${HOME}/.config/BetterDiscord/plugins
mkdir -p ${HOME}/.config/BetterDiscord/themes

ln -sf ${PWD}/discord_settings.json ${HOME}/.config/discord/settings.json

# copy instead if link otherwise betterdiscord cannot see file changes
#ln -sf ${PWD}/wal.theme.css ${HOME}/.config/BetterDiscord/themes/
cp ${PWD}/wal.theme.css ${HOME}/.config/BetterDiscord/themes/wal.theme.css

# download plugins
wget "https://github.com/JustOptimize/ShowHiddenChannels/releases/download/v0.6.4/ShowHiddenChannels.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/ShowHiddenChannels.plugin.js
wget "https://raw.githubusercontent.com/1Lighty/BetterDiscordPlugins/refs/heads/master/Plugins/MessageLoggerV2/MessageLoggerV2.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/MessageLoggerV2.plugin.js
wget "https://raw.githubusercontent.com/Colonial-Dev/WayAFK/refs/heads/master/WayAFK.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/WayAFK.plugin.js
wget "https://raw.githubusercontent.com/Farcrada/DiscordPlugins/7f1c3f98461bcf1b336c2df6e28ca025d09d03cb/Double-click-to-edit/DoubleClickToEdit.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/DoubleClickToEdit.plugin.js
wget "https://raw.githubusercontent.com/TheCommieAxolotl/BetterDiscord-Stuff/1b9a38609200d08886be9bba7f4df425eafbf561/Timezones/Timezones.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/Timezones.plugin.js
wget "https://raw.githubusercontent.com/TheCommieAxolotl/BetterDiscord-Stuff/38b22daa8db787b24a60730e51cfd0f757949704/BetterSyntax/BetterSyntax.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/BetterSyntax.plugin.js
wget "https://raw.githubusercontent.com/TheLazySquid/BetterDiscordPlugins/d4ff127db89318d2361086e0e85251fcc72e4fed/plugins/ZipPreview/ZipPreview.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/ZipPreview.plugin.js
wget "https://raw.githubusercontent.com/binarynoise/open-in-mpv/acc203b0b4e7813cb072600972a9214f70b6ed73/open-in-mpv.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/open-in-mpv.plugin.js
wget "https://raw.githubusercontent.com/mwittrien/BetterDiscordAddons/50d8a379b9e98e114a3e4f20871ae1aaea13ab8d/Plugins/LastMessageDate/LastMessageDate.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/LastMessageDate.plugin.js
wget "https://raw.githubusercontent.com/mwittrien/BetterDiscordAddons/c756d0ed59938a7713458b7e3f2b36f868598f68/Plugins/BetterNsfwTag/BetterNsfwTag.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/BetterNsfwTag.plugin.js
wget "https://raw.githubusercontent.com/mwittrien/BetterDiscordAddons/c756d0ed59938a7713458b7e3f2b36f868598f68/Plugins/ServerCounter/ServerCounter.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/ServerCounter.plugin.js
wget "https://raw.githubusercontent.com/zerebos/BetterDiscordAddons/6d839d0ab65371819b081218bc43b09d7d6e762d/Plugins/DoNotTrack/DoNotTrack.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/DoNotTrack.plugin.js
