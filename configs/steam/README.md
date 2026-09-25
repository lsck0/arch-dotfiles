# Steam cyberpunk theme

Cyberpunk/hacker dark theming for the modern Steam client (the 2023+ Chromium
"Steam UI"), matching the rest of the rice: dark ground, wal accent, sharp
corners, thin accent scrollbars, Tektur on text controls.

## Mechanism

The modern Steam client is a Chromium app, so theming is CSS injection. This
theme uses **[Millennium](https://github.com/SteamClientHomebrew/Millennium)**,
the currently-maintained loader that injects per-window CSS. The older SFP /
steam-friends-patcher and plain `~/.local/share/Steam/skins` skins no longer
work on this client, so they are not used.

Millennium loads a theme from `~/.local/share/Steam/steamui/skins/<name>/`. With
`UseDefaultPatches` in `skin.json`, it auto-injects three files by name:

- `libraryroot.custom.css` -> main window
- `friends.custom.css` -> friends/chat window
- `bigpicture.custom.css` -> Big Picture

Each of those `@import`s `shared.css` (the cyberpunk rules) and `colors.css`
(the palette, imported last so it wins the cascade).

## Colors are dynamic (track pywal)

`colors.css` is a symlink to `~/.cache/wal/colors-steam.css`, which wallust
renders from `configs/wallust/templates/wal/colors-steam.css` on every wallpaper
switch (the `wal/` template dir is auto-rendered by `wallust run`/`wallust cs`,
which `scripts/switch-wallpaper.sh` already calls -- no edit to that script is
needed). The theme therefore tracks the wallpaper palette. New colors appear on
the next Steam launch or Millennium reload; running Steam does not restyle live.
If the palette file is missing, the static `:root` fallbacks in `shared.css`
keep the theme dark and correct.

## Install

1. Install Millennium (manual step, like spicetify):

   ```
   yay -S millennium
   ```

   It is listed in `install.sh` under `# [gaming]`.

2. Link the theme into the skins dir (done by the repo's linker, or directly):

   ```
   configs/steam/link.sh
   ```

3. Launch Steam through Millennium once so it patches the client:

   ```
   ~/.millennium/start.sh
   ```

## Manual enable step

In Steam: Settings -> Themes -> Client Theme -> pick **Cyberpunk**. Restart
Steam if it does not apply immediately.

## Notes

- Steam's inner class names are hashed, so `shared.css` sticks to robust global
  rules (background, scrollbars, selection, corners, focus glow, form fields);
  it is a solid foundation, not a per-widget reskin.
- Tektur is applied to text controls only (`body, button, input, textarea,
  select`); Steam sets its own font-family on many containers, so some text
  keeps Steam's font, and this avoids clobbering its icon glyphs.
