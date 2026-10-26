# gaming

Extends the root `AGENTS.md`. Game launchers, performance tooling and the game network path.

## Modules

- `dalamud`: the FFXIV plugin runtime; plugin manifests in `configs/secrets/state/dalamud/manifests`, config and plugin
  configs per machine in `configs/secrets/state/dalamud/<host>` (its `backup` verb), plugins reinstalled from their repos
  by `plugin-restore.nu`.
- `d2launcher`: the Diablo II / Median XL launcher, a pinned upstream checkout (it has no aur package) plus its config
  and desktop entry; its bulk downloads (the game, the proton build, median xl patches, save backups and the wine
  prefix) live in `~/sync/vendor/d2launcher`, reached through symlinks because the script hardcodes
  `~/.d2launcher/{bin,patches,backup}`. Without that synced dir the vendor dir is `$XDG_DATA_HOME/d2launcher-vendor`
  and the module fetches the launcher's wine itself (Kron4ek `wine-7.0-5-proton`, pinned sha256; it reports
  `wine-5.12-...`), so vanilla LoD and `pd2` set up on a fresh install too. `bin/diablo2` is seeded from a Lord of Destruction install (`base_dir`, detected
  in the lutris prefixes, else under `~/sync/games/d2`). The game runs inside gamescope (`gamescope.sh`, the launcher's `custom_command`) at a 4:3
  `render_size`, so its window resizes freely; its stream is named "Diablo II" through `PIPEWIRE_ALSA`.
- `pd2`: Project Diablo 2 single player, two seasons side by side, each in its own tree (`~/.local/share/pd2-s14`,
  `~/.local/share/pd2`): a `Diablo II` dir linking the lutris LoD files with `ProjectD2` inside it (PD2's dll refuses a
  dir outside a LoD install), its own prefix and `pd2.sh`, all on d2launcher's wine 5.12 (the system's wine-staging
  overflows the 1.13c Game.exe's stack) with cnc-ddraw (`ddraw=n,b`) inside gamescope.
  - Season 14 ("Project Diablo II"): the client from PD2's own host `pd2-client-files.projectdiablo2.com`, every file
    pinned by sha256 in `s14-client.nuon` (`pd2-pin.nu` re-pins it from the official `metadata.json` md5s after a PD2
    patch). Runs `Game.exe` without PlugY: S14 has its own shared stash (`pd2_shared.stash`) and tabs. Its save dir is
    `classic_game_settings.other.save_path` in `ProjectD2/ProjectDiablo.json` (not the registry), merged from
    `s14_save_dir`, `~/sync/games/d2/Save-S14`.
  - Season 3 ("Project Diablo II S3"): the old install (`game_dir`, `~/sync/games/d2/ProjectD2`) with PlugY (big
    stash, stat and skill unassign: `PlugY.ini`) and its saves (`save_dir`, `~/sync/games/d2/Save`, the prefix's
    `Save Path`). They can't move to S14: PD2-Converter stops at season 8 and nothing edits S14's stash.
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
