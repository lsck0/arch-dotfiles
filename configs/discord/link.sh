#!/bin/env bash

set -ex

mkdir -p ${HOME}/.config/discord
mkdir -p ${HOME}/.config/BetterDiscord/plugins
ln -sf ${PWD}/discord_settings.json ${HOME}/.config/discord/settings.json

wget "https://github.com/JustOptimize/ShowHiddenChannels/releases/download/v0.5.6/ShowHiddenChannels.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/ShowHiddenChannels.plugin.js
wget "https://raw.githubusercontent.com/1Lighty/BetterDiscordPlugins/refs/heads/master/Plugins/MessageLoggerV2/MessageLoggerV2.plugin.js" -O ${HOME}/.config/BetterDiscord/plugins/MessageLoggerV2.plugin.js
