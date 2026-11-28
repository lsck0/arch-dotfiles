# Steam

Millennium with the cyberpunk theme; wallust renders `colors.css` into the theme dir, applied on the next Steam start.
`steam-bootstrap` links millennium into Steam's runtime once it exists. An apply reruns it while a link is missing; the
user-hook that calls it is dropped by the next apply once `libXtst` is linked.

First run: start Steam once, then restart it. If Steam was open during the apply, pick the theme by hand
(Settings, Themes, Client Theme, Cyberpunk).

`steam-launch.nu` starts Steam with OBS capture, first running `steam-launch-options.nu`, which sets
`ENABLE_VKBASALT=1 gamemoderun mangohud %command%` (vkBasalt, `gaming/vkbasalt`) on newly installed games, never on
Steam's own tools (Proton, the runtimes).
Gamemode and MangoHud stay per game: gamemode preloaded into the client breaks the webhelper, and `MANGOHUD=1` on the
client makes its fossilize_replay helper abort at exit. Launch options set by hand are kept.
