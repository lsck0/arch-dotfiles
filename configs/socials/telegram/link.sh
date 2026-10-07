#!/usr/bin/env bash

# telegram lives in /usr/sbin, not always on PATH
if ! command -v Telegram >/dev/null 2>&1 && [ ! -x /usr/sbin/Telegram ]; then
    exit 0
fi

mkdir -p "${HOME}/.cache/wal" "${HOME}/.local/share/TelegramDesktop"

# stable import path for the wallust-rendered palette
cache="${HOME}/.cache/wal/colors-telegram.tdesktop-palette"
ln -sfn "$cache" "${HOME}/.local/share/TelegramDesktop/pywal-cyberpunk.tdesktop-palette"
