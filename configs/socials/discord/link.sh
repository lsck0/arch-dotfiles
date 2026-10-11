#!/usr/bin/env bash

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
    "https://raw.githubusercontent.com/TheLazySquid/BetterDiscordPlugins/3ce443c86a14185b2b2d088e9be49b8245d17c6c/plugins/ZipPreview/ZipPreview.plugin.js" \
    "https://raw.githubusercontent.com/zerebos/BetterDiscordAddons/6d839d0ab65371819b081218bc43b09d7d6e762d/Plugins/DoNotTrack/DoNotTrack.plugin.js" \
    "https://raw.githubusercontent.com/Atamol/BetterDiscordPlugins/a0800b14b2462c4af1361dd9c79490b88ff649b6/BetterDoubleClickToEdit/BetterDoubleClickToEdit.plugin.js" \
    "https://raw.githubusercontent.com/Atamol/BetterDiscordPlugins/4474ed05346b0b413ee69feaf941a834b84209ea/DoubleClickToReply/DoubleClickToReply.plugin.js" \
    "https://raw.githubusercontent.com/Avasay-Sayava/BetterDiscordPlugins/f815fab3901db71fbe208bc3187d1ab146b0a24d/LaTeXGenerator/LaTeXGenerator.plugin.js" \
    "https://raw.githubusercontent.com/BinaryQuantumSoul/discord-latex/a2051554763d1bbfde1d540def8a9efb965dadcf/dist/LaTeX.plugin.js" \
    "https://raw.githubusercontent.com/Snusene/BetterDiscordPlugins/a60205b18f394a2a2bf664194ab251532369dfc3/PriorityDM/PriorityDM.plugin.js" \
    "https://raw.githubusercontent.com/Snusene/BetterDiscordPlugins/c53818992addc44fa3c3dcea4567a2ff3c9bdb2a/Incognito/Incognito.plugin.js" \
    "https://raw.githubusercontent.com/Kawtious/HighResProfileImages/402830211b48dfd57ff4f4641722c29de2a9f279/HighResProfileImages.plugin.js" \
    "https://raw.githubusercontent.com/fluzzeon/betterdiscord-OpenInApp/2b1f7c2c05af8abb16529dc9c248a224a15492c3/OpenInApp.plugin.js" \
    "https://raw.githubusercontent.com/Skamt/BDAddons/20be7c0e79ddd8b7e6d290c14ebe49aef5f7f650/SpotifyEnhance/SpotifyEnhance.plugin.js" \
    "https://raw.githubusercontent.com/Farcrada/DiscordPlugins/c1250d3990ed3b9f1bf3518aa68050402929c52b/Hide-Chat-Icons/HideChatIcons.plugin.js" \
    "https://raw.githubusercontent.com/zerebos/BetterDiscordAddons/49cdbe56ffc5d9d815663d83454cbe361af2b2cf/Plugins/PermissionsViewer/PermissionsViewer.plugin.js"; do
    f="${bd}/plugins/${url##*/}"
    [[ "$(cat "${f}.url" 2>/dev/null)" == "$url" ]] && continue
    wget -q "$url" -O "${f}.tmp" && mv "${f}.tmp" "$f" && echo "$url" > "${f}.url"
done

user_hook_install ./hook betterdiscord-inject
