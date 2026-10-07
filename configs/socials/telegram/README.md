# Telegram Desktop theming

Telegram cannot load a palette from disk or hot-reload one (tdesktop#31183),
so importing is a manual step, repeated after each wallpaper switch.

Wallust renders `../../base/wallust/templates/wal/colors-telegram.tdesktop-palette` to
`~/.cache/wal/`; `link.sh` symlinks it to
`~/.local/share/TelegramDesktop/pywal-cyberpunk.tdesktop-palette`.

## Import

1. Settings > Chat Settings > Theme.
2. Open the `...` menu next to the themes.
3. Create new theme > Import theme.
4. Pick `~/.local/share/TelegramDesktop/pywal-cyberpunk.tdesktop-palette`.
5. Save the theme.
