# Steam

Millennium with the cyberpunk theme; wallust renders `colors.css` into the theme dir, applied on the next Steam start.
`steam-bootstrap` links millennium into Steam's runtime once it exists. It reruns on every apply; the user-hook that
calls it is dropped by the next apply once `libXtst` is linked.

First run: start Steam once, then restart it. If Steam was open during the apply, pick the theme by hand
(Settings, Themes, Client Theme, Cyberpunk).

`steam-launch.nu` starts Steam with the mangohud overlay and OBS capture, and sets `gamemoderun mangohud %command%` on
newly installed games. Gamemode stays per game: preloaded into the client it breaks the webhelper. Launch options set
by hand are kept.
