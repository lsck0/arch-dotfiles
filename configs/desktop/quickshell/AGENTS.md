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
  alert, reminders, speedtest, disk-speedtest, image-picker, wifiqr, tasks).
- `Commons/`: singletons and shared logic. Palette and style tokens live in `Colors.qml`, `Theme.qml`, `Style.qml`;
  also `Audio.qml`, `Cava.qml`, `Paths.qml`, `TimerState.qml` and `TaskState.qml` (the one taskwarrior export), `Power.qml`, `Util.qml`, the `*Process.qml` helpers.
- `Ui/`: reusable widgets (buttons, panels, sliders, the hud/overlay chrome).
- `services/`: `AppLibrary.qml`, `AppSearch.js`, `hidden-entries.nu`.
- `scripts/`: shell-side helpers the plugins call (media keys, brightness, network qr/speedtest, pomodoro, reminders,
  wallpaper picker).
- `shaders/`: the glitch effect (`.frag` plus compiled `.qsb`).

## IPC and reload

- Summon a panel: `quickshell ipc call shell summon <id> [json]`; the payload is parsed and handed to the plugin's `open()`.
- `shell` target also exposes `palette()` (the conditioned palette plus fx, for `toggle-shader.nu` and anything themed
  after the shell) and `reloadPowerMode()`.
- `discord` target: `toggleMute`, `toggleDeafen`, `disconnect` (reached from hyprland keybinds).
- `mod.nu` copies the tree into `~/.config/quickshell` (only `theme.json` stays a link, edited live); quickshell
  reloads on `dot apply desktop/quickshell`, never while the lock is held. `restart.nu` restarts the unit
  (`quickshell.service`). See the `l-dotfiles-quickshell-dev` skill for logs and screenshots.

## Palette

- Colors come from wallust/themes (`core/wallust`, `themes/`) into `Colors.qml`/`Theme.qml`; widgets read the
  tokens, never hardcode a color. A theme switch recolors the shell through these.
