# Steam cyberpunk theme

Millennium theme; wallust renders `colors.css` into the theme dir (millennium ignores links out of it), so new colors
apply on the next Steam launch.

## Install

`dot apply --packages` installs `millennium` (this module's meta) and `dot apply gaming/steam` sets it up.

The module copies the theme, seeds the palette and, until Steam has bootstrapped, arms the `steam-bootstrap` user path
unit, which links millennium into Steam's runtime dirs once they exist, removes the `steam.desktop` the bootstrap
copies into the desktop dir, and then removes itself. Steam updates do not touch those links.

1. Launch Steam once so it bootstraps, then restart it to load millennium.
2. The module sets the active theme in `~/.config/millennium/config.json`, creating it before the first run; with
   Steam open while it ran, pick it by hand: Settings -> Themes -> Client Theme -> **Cyberpunk**.

## Launching

The launcher entry runs `steam-launch.nu`, which gives every game the hidden mangohud overlay (shift+f12, see
`gaming/mangohud`) and obs capture, and first runs `steam-launch-options.nu` so a game installed since then gets
`gamemoderun mangohud %command%`. Gamemode is per game: preloaded into the client it would register steam and
steamwebhelper, which breaks the webhelper's websocket ("Unexpected Transport Error") and keeps gamemode on while Steam
idles. Per game it can differ: PNGTuber Plus gets `gamemoderun obs-gamecapture %command%`, without mangohud, whose
GL hook would bypass obs_glcapture's. A launch option set by hand is kept; one this script wrote follows its current
value.
