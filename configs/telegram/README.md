# Telegram Desktop theming

Cyberpunk/hacker palette for Telegram Desktop that tracks the wallust/pywal
palette, so Telegram matches the rest of the rice.

Telegram cannot load a palette from disk on its own and has no reload hook
(tdesktop#31183), so the import is a one-time manual step -- like `spicetify apply`
or Proton auth. Once imported, the palette lives inside Telegram; a re-import is
only needed when you want to pull in a new colour scheme after a wallpaper switch.

## Files

- `../wallust/templates/wal/colors-telegram.tdesktop-palette` -- the dynamic
  source. Wallust renders it into `~/.cache/wal/colors-telegram.tdesktop-palette`
  on every wallpaper/theme switch (same mechanism as `colors-yazi.toml`,
  `colors-nushell.nu`). Colours are pywal placeholders; no hardcoded hex.
- `pywal-cyberpunk.tdesktop-palette` -- a static example snapshot of the current
  palette, for reference only. The live file is the rendered one above.
- `link.sh` -- exposes a stable import path and seeds the cache file on first run.

## One-time manual import

`link.sh` symlinks a stable, always-current path to the rendered palette:

    ~/.local/share/TelegramDesktop/pywal-cyberpunk.tdesktop-palette

In Telegram Desktop:

1. Settings > Chat Settings > Theme.
2. Scroll to the theme row, open the `...` (more) menu next to the themes.
3. Choose "Create new theme" > "Import theme" (or drag the file onto the window).
4. Pick `~/.local/share/TelegramDesktop/pywal-cyberpunk.tdesktop-palette`
   (the file picker filters for `*.tdesktop-palette` / `*.tdesktop-theme`).
5. Save the theme. Telegram now uses the imported colours.

The palette defines all base colours, so it themes correctly on its own; you do
not need a specific built-in base theme selected first.

## After a wallpaper switch

Wallust re-renders the palette automatically, but Telegram holds the imported
copy in its own storage and cannot hot-reload it. To pull in the new colours,
re-import the same file (steps above); the symlink already points at the fresh
render, so just import it again. This is the accepted manual step.

## Format notes

- One `key: value;` per line. `value` is `#rrggbb` or `#rrggbbaa` (alpha last),
  or another key name, which inherits that key's colour.
- Accent is `color4`; the dark base is `background` / `color0`. Text and icons on
  accent fills use `color0` for contrast.
