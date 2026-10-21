# gaming

Extends the root `AGENTS.md`. Game launchers, performance tooling and the game network path.

## Modules

- `dalamud`: the FFXIV plugin runtime; plugin manifests in `configs/secrets/state/dalamud/manifests`, config and plugin
  configs per machine in `configs/secrets/state/dalamud/<host>` (its `backup` verb), plugins reinstalled from their repos
  by `plugin-restore.nu`.
- `d2launcher`: the Diablo II / Median XL launcher, a pinned upstream checkout (it has no aur package) plus its config
  and desktop entry; its bulk downloads (the game, the proton build, median xl patches, save backups and the wine
  prefix) live in `~/sync/vendor/d2launcher`, reached through symlinks because the script hardcodes
  `~/.d2launcher/{bin,patches,backup}`. `bin/diablo2` is seeded from a Lord of Destruction install (`base_dir`, detected
  in the lutris prefixes). The game runs inside gamescope (`gamescope.sh`, the launcher's `custom_command`) at a 4:3
  `render_size`, so its window resizes freely; its stream is named "Diablo II" through `PIPEWIRE_ALSA`.
- `ffxiv`: the FFXIV client and launcher config, seeded once from `configs/secrets/state/ffxiv/<host>` (its `backup`
  verb).
- `gamemode`: feral gamemode (`gamemode.ini`, its `[gpu]` from the detected card), engaged per game through a launch
  option.
- `lutris`: the non-Steam game manager, its wine dpi from the main monitor's scale.
- `mangohud`: the performance overlay, loaded hidden into every steam and xivlauncher game; `mangohud-toggle`
  (shift+f12, a hyprland bind) flips it through its control socket, its own `toggle_hud` stays off.
- `modrinth`: the Modrinth Minecraft launcher; launcher state in `configs/secrets/keys/modrinth/<host>` (its `backup`
  verb), worlds sync via `~/sync` (only into a saves dir syncthing made).
- `nethack`: nethack with a tmpfiles-backed bones/score dir.
- `protonup`: manages Proton-GE versions for Steam.
- `steam`: Steam, the launch-option writer and themes (see below).
- `vkbasalt`: the Vulkan post-processing layer.
- `games`, `emulators`, `vr`, `runtime`: packages only (launchers, emulators, the VR stack, proton/vkd3d/vulkan tools).
- `vpn-bypass`: routes game traffic around the ProtonVPN tunnel (the games-bypass nft set, service and route script).

## Conventions

- gamemode engages per game through a Steam launch option in `localconfig.vdf`, not globally; the same option adds
  the `mangohud` wrapper for OpenGL games, `MANGOHUD=1` from `steam-launch.nu` covers vulkan.
  `steam-launch-options.nu` writes `gamemoderun mangohud %command%` for installed games that have none, is
  idempotent, backs up the file, and refuses to run while Steam is open (Steam rewrites the file on exit);
  `steam-launch.nu` runs it before every Steam start, so a game installed later gets it on the next launch.
- Games bypass the VPN by design: `vpn-bypass` marks game traffic so it flows on the real link. Torrents go the
  opposite way, bound to the tunnel (`desktop/qbittorrent`).
- Game saves and launcher state have one home each: live saves and worlds to `~/sync`, launcher/account state
  restored by the module's `link` from `configs/secrets/` or `~/sync`. Game installs are re-downloadable and
  not backed up.
