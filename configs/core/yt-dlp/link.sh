#!/usr/bin/env bash

link_into "${XDG_CONFIG_HOME:-$HOME/.config}/yt-dlp" config
# auto-route wrapper: ~/.local/bin/yt-dlp -> yt-dlp.sh, ahead of /usr/bin on PATH
link_commands yt-dlp.sh
