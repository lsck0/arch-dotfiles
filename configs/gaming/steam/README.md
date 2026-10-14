# Steam cyberpunk theme

Millennium theme; wallust renders `colors.css` into the theme dir (millennium ignores links out of it), so new colors
apply on the next Steam launch.

## Install

`dot install` installs `millennium` (this module's meta) and `dot link gaming/steam` sets it up.

The module copies the theme, seeds the palette and, until Steam has bootstrapped, arms the `millennium-link` user path
unit, which links millennium into Steam's runtime dirs once they exist and then removes itself. Steam updates do not
touch those links.

1. Launch Steam once so it bootstraps, then restart it to load millennium.
2. The module sets the active theme in `~/.config/millennium/config.json`, creating it before the first run; with
   Steam open while it ran, pick it by hand: Settings -> Themes -> Client Theme -> **Cyberpunk**.

## Launching

The launcher entry runs `steam-launch.nu`, which gives every game the mangohud overlay and obs capture. Gamemode is per
game: set its launch options to `gamemoderun %command%`. Preloaded into the client it would register steam and
steamwebhelper, which breaks the webhelper's websocket ("Unexpected Transport Error") and keeps gamemode on while Steam
idles.
