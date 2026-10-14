# gaming

Extends the root `AGENTS.md`. Game launchers, performance tooling and the game network path.

## Modules

- `dalamud`: the FFXIV plugin runtime; config and plugin manifests in `secrets/dalamud` (its `backup` verb), plugins
  reinstalled from their repos by `plugin-restore.nu`.
- `ffxiv`: the FFXIV client and launcher config, seeded once from `secrets/ffxiv` (its `backup` verb).
- `gamemode`: feral gamemode (`gamemode.ini`, its `[gpu]` from the detected card), engaged per game through a launch
  option.
- `lutris`: the non-Steam game manager, its wine dpi from the main monitor's scale.
- `mangohud`: the performance overlay, engaged per game through a launch option.
- `modrinth`: the Modrinth Minecraft launcher; launcher state in `secrets/modrinth` (its `backup` verb), worlds
  sync via `~/sync` (only into a saves dir syncthing made).
- `nethack`: nethack with a tmpfiles-backed bones/score dir.
- `protonup`: manages Proton-GE versions for Steam.
- `steam`: Steam, the launch-option writer and themes (see below).
- `vkbasalt`: the Vulkan post-processing layer.
- `games`, `emulators`, `vr`, `runtime`: packages only (launchers, emulators, the VR stack, proton/vkd3d/vulkan tools).
- `vpn-bypass`: routes game traffic around the ProtonVPN tunnel (the games-bypass nft set, service and route script).

## Conventions

- gamemode and MangoHud engage per game through a Steam launch option in `localconfig.vdf`, not globally.
  `steam-launch-options.nu` writes `gamemoderun mangohud %command%` for installed games that have none, is
  idempotent, backs up the file, and refuses to run while Steam is open (Steam rewrites the file on exit).
- Games bypass the VPN by design: `vpn-bypass` marks game traffic so it flows on the real link. Torrents go the
  opposite way, bound to the tunnel (`desktop/qbittorrent`).
- Game saves and launcher state have one home each: live saves and worlds to `~/sync`, launcher/account state
  restored by the module's `link` from `secrets/` or `~/sync`. Game installs are re-downloadable and
  excluded from borg (see root backup model).
