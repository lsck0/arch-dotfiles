# desktop

- Hyprland: `hyprland/AGENTS.md`. quickshell: `quickshell/AGENTS.md` and `l-dotfiles-quickshell-dev`. Audio:
  `pipewire/AGENTS.md`.
- GUI programs take the palette from wallust/oomox templates; a theme switch writes only outside the repo.
- `qbittorrent` is bound to its `interface` option, `proton0` where the profile has secrets. dolphin has no terminal:
  dolphinrc's kiosk restrictions drop its terminal panel and actions; kdeglobals' `TerminalApplication` is ghostty.
- Browsers force-install their extensions by policy: firefox's `FORCED_EXTENSIONS` (`config/policies.json`, left out
  per machine with `extensions_off`), chromium's `ExtensionInstallForcelist` (`config/policy.json`).
- `applications`: Stirling PDF serves on `localhost:8090` (`STIRLING_PORT`), since caido holds its default 8080.
- `kdeconnect`: the phone link (`phone share|clipboard`, SUPER+u and SUPER+SHIFT+u); ports 1714-1764 open on
  trusted links only (`base/nftables`); `clipboard_auto` writes each paired device's `kdeconnect_clipboard/config`
  (`autoShare`, never `sendPassword`).
