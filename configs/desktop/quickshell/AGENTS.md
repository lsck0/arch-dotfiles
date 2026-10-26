# desktop/quickshell

Extends the root `AGENTS.md` and the `configs/desktop/AGENTS.md`. The quickshell desktop shell: bar, launcher,
lock, notifications, OSD and overlays. QML.

## Layout

- `shell.qml`: the `ShellRoot`. Instantiates one `Bar` per screen (`Variants` over `Quickshell.screens`), loads the
  `Plugins.js` shell table (each once), owns `mainScreenName`, per-widget saved state (`widget-settings.json`), and
  the `IpcHandler`s.
- `plugins/Plugins.js`: the registry. `shell` maps a summon id (`panel.*`, `service.*`) to a QML file; `bar`/`barSecondary`
  map bar positions (left/center/right) to widget names under `plugins/bar/widgets`.
- `plugins/`: one dir per feature (bar, background, osd, clipboard, appsearch, power, overview, lock, notifications,
  alert, reminders, speedtest (network and disk), image-picker, wifiqr, tasks, `desktop` (the bottom-layer agenda and
  notes cards), `settings` (the settings window over `dot set --json`, `Schema.js`)).
- `Commons/`: singletons and shared logic. Palette and style tokens live in `Colors.qml`, `Theme.qml`, `Style.qml`,
  `Border.qml`, `Palette.js` (generated from `palette.nu`); also `Audio.qml`, `Cava.qml`/`CavaRef.qml`, `Paths.qml`,
  `TimerState.qml` and `TaskState.qml` (the one taskwarrior export), `Power.qml`, `Util.qml`, `DiscordControl.qml`
  (the BetterDiscord voice plugin's channel), `ToggleEvents.qml`, the `*Process.qml` helpers (`ObsProcess.qml`: the
  obs websocket).
- `Ui/`: reusable widgets (buttons, panels, sliders, the hud/overlay chrome).
- `services/`: `AppLibrary.qml`, `AppSearch.js`, `hidden-entries.nu`.
- `scripts/`: shell-side helpers the plugins call (media keys, brightness, network qr/speedtest, pomodoro, reminders,
  wallpaper picker).
- `shaders/`: the glitch effect (`.frag` plus compiled `.qsb`).

## IPC and reload

- Summon a panel: `quickshell ipc call shell summon <id> [json]`; the payload is parsed and handed to the plugin's `open()`.
- `shell` target also exposes `palette()` (the conditioned palette plus fx, for `toggle-shader.nu` and anything themed
  after the shell), `rgb(c)` and `reloadPowerMode()`.
- Every `IpcHandler` target and its functions:
  - `shell` (`shell.qml`): `palette`, `rgb`, `reloadPowerMode`, `summon`.
  - `discord` (`shell.qml`): `toggleMute`, `toggleDeafen`, `disconnect` (reached from hyprland keybinds).
  - `bar` / `bar-<output>` (`plugins/bar/Bar.qml`): `open <panel>`, `close`, `toggle <panel>`, `state`, `list`.
  - `appsearch`, `powermenu`, `tasks`: `toggle`, `open`, `close`; `clipboard` adds `forget <hash>`; `overview` adds
    `next`, `prev`, `commit`.
  - `settings` (`plugins/settings/Settings.qml`): `toggle`, `open`, `close`, `openOn <output>`.
  - `notifications`: `dndState`, `toggleDnd`, `setDnd <value>`, `isDnd`, `showHistory`, `clear`, `dismissAll`,
    `dismissOne`, `invokeLast`, `dismiss <summary>`, `ping`.
  - `osd`: `present <json>`, `close`, `state`, `ping`. `lock`: `lock`, `isLocked`.
  - `background`: `refresh`, `set <path>`, `setInstant <path>`.
  - `obs` (`Commons/ObsProcess.qml`): `toggleListen`, `listen <bool>`, `listening`.
  - `toggles` (`Commons/ToggleEvents.qml`): `changed <script>`, called by `scripts/toggles/lib.nu` after a flip.
- `mod.nu` copies the tree into `~/.config/quickshell`, `theme.json` included: a live edit is drift, change the repo
  file and apply; quickshell reloads on `dot apply desktop/quickshell`, never while the lock is held. `restart.nu` restarts the unit
  (`quickshell.service`). See the `l-dotfiles-quickshell-dev` skill for logs and screenshots.

## Palette

- Colors come from wallust/themes (`core/wallust`, `themes/`) into `Colors.qml`/`Theme.qml`; widgets read the
  tokens, never hardcode a color. A theme switch recolors the shell through these.
