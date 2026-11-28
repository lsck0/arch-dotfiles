# gaming

- `d2launcher`: pinned checkout; bulk data and prefix in `$XDG_DATA_HOME/d2launcher-vendor`: the owner's copied from
  the NAS's vendor dir (`core/nas/scripts/vendor.nu`) when its patch version is newer, anyone else's built with a
  pinned wine fetch. The LoD base comes from a lutris prefix or `~/sync/games/d2`. Games run in gamescope from one
  `gamescope.sh` template: median xl, plain Diablo II: Lord of Destruction (`diablo2.sh`) and both pd2 seasons.
- `pd2`: two seasons, each with its own tree, prefix and `pd2.sh`, on d2launcher's wine with `ddraw=n,b` in gamescope.
  S14 ("Project Diablo II") from PD2's client host, pinned in `s14-client.nuon` (`pd2-pin.nu` re-pins; its `update`
  verb warns in `dot sync` once `metadata.json` left the pins), saves in `~/sync/games/d2/Save-S14` via
  `ProjectDiablo.json`, no PlugY. S3 ("Project Diablo II S3") keeps PlugY and `~/sync/games/d2/Save`; its saves can't
  move to S14.
- Gamemode, the MangoHud wrapper and `ENABLE_VKBASALT` are a per-game Steam launch option written by
  `steam-launch-options.nu` (never on Steam's tools), which refuses while Steam runs (Steam rewrites `localconfig.vdf`
  on exit). Millennium hooks the 64-bit client through `steamrt64/libXtst.so.6` ->
  `/run/host/usr/lib/millennium/libmillennium_bootstrap_x64.so` (pressure-vessel sees the host under `/run/host`);
  `steam/scripts/steam-bootstrap.nu` links it. A beta Millennium sorting above the release is
  caught by `dot status` `stuck`.
- Games bypass the VPN (`vpn-bypass`); torrents are bound to qbittorrent's `interface`, `proton0` where the profile
  has secrets (`desktop/AGENTS.md`).
- Saves and worlds live in `~/sync`, launcher state in `configs/secrets/` via `backup`/`link`; installs are not backed
  up. A live save dir becomes a link into `~/sync` through `sync-link` (`games`, `modrinth`, `d2launcher`); one that
  holds other data stays, with a note on every apply until Luca merges it by hand. `modrinth`'s backup copies `app.db`
  only when a login table changed (`LOGIN_TABLES`).
