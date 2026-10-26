# gaming

- `d2launcher`: pinned checkout; bulk data in `~/sync/vendor/d2launcher` (else `$XDG_DATA_HOME/d2launcher-vendor` plus
  a pinned wine fetch). The LoD base comes from a lutris prefix or `~/sync/games/d2`. Games run in gamescope.
  `vanilla.sh` is plain Diablo II: Lord of Destruction.
- `pd2`: two seasons, each with its own tree, prefix and `pd2.sh`, on d2launcher's wine with `ddraw=n,b` in gamescope.
  S14 ("Project Diablo II") from PD2's client host, pinned in `s14-client.nuon` (`pd2-pin.nu` re-pins), saves in
  `~/sync/games/d2/Save-S14` via `ProjectDiablo.json`, no PlugY. S3 ("Project Diablo II S3") keeps PlugY and
  `~/sync/games/d2/Save`; its saves can't move to S14.
- Gamemode and the MangoHud wrapper are a per-game Steam launch option written by `steam-launch-options.nu`, which
  refuses while Steam runs (Steam rewrites `localconfig.vdf` on exit).
- Games bypass the VPN (`vpn-bypass`); torrents are bound to it.
- Saves and worlds live in `~/sync`, launcher state in `configs/secrets/` via `backup`/`link`; installs are not backed
  up. dot never writes into `~/sync`.
