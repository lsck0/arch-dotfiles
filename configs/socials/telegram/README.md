# Telegram

Telegram can't load or reload a palette from disk (tdesktop#31183), so import it by hand after each theme switch:
Settings, Chat Settings, Theme, `...`, Create new theme, Import theme,
`~/.local/share/TelegramDesktop/wallust.tdesktop-palette`, Save. The theme switch rewrites that file.
