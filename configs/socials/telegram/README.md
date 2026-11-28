# Telegram

The theme switch writes `~/.local/share/TelegramDesktop/wallust.tdesktop-theme`: the palette plus a plain chat
background in its `windowBg` colour (a bare palette leaves Telegram's green pattern). Apply it once from Telegram, so
it keeps the file's path: Settings, Chat Settings, `...`, Choose from file, that file, Apply. Telegram ignores a theme
file passed on its command line.

From then on Telegram watches the file and applies each rewrite at once while it runs (tdesktop's
`ChatBackground::refreshThemeWatcher`). A switch made while Telegram is closed shows at the next one: it starts from
its cached copy.

Do not import it through Create new theme: that saves a cloud copy, and Telegram then watches the copy, not this file.
