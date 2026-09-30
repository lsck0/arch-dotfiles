# Steam cyberpunk theme

Millennium theme; `colors.css` links to the wallust-rendered
`~/.cache/wal/colors-steam.css`, so new colors apply on the next Steam launch.

## Install

`install.sh` installs `millennium` (gaming group) and runs `configs/steam/link.sh`. By hand: `yay -S millennium`,
then `configs/steam/link.sh`.

`link.sh` links the theme, seeds the palette and arms the `millennium-link` user path unit, which links millennium
into Steam's runtime dirs once they exist and again after every Steam update.

1. Launch Steam once so it bootstraps, then restart it to load millennium.
2. Steam: Settings -> Themes -> Client Theme -> **Cyberpunk**. Skip this if `link.sh` already found
   `~/.config/millennium/config.json`, it sets the active theme there.
