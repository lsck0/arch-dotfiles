# desktop/quickshell

Editing, reload, logs, screenshots: `l-dotfiles-quickshell-dev`.

- `config/shell.qml`: one `Bar` per screen, loads `plugins/Plugins.js` (summon ids), owns the `shell` and
  `discord` IPC targets; every other target lives in the plugin or `Commons/` singleton it drives.
- `plugins/<feature>/`, `Commons/` (singletons: palette, style, audio, tasks, timers, calendar, notes), `Ui/` (shared
  widgets), `scripts/` (helpers the plugins call; `scripts/lib/shell.nu` holds their action notification, bounded
  IPC call, atomic state write and timer epochs), `services/` (`AppLibrary`, `AppSearch`), `shaders/` (baked by `restart.nu prepare`), `sounds/`.
- IPC: `quickshell ipc -p ~/.config/quickshell show` lists every target; panels open with
  `quickshell ipc call shell summon <id> <json>` (`{}` without a payload; the argument is required) or
  `quickshell ipc call bar open <panel>`.
- Settings window (`plugins/settings/`): a UI over `dot set --json` and `dot status --json`; MACHINE (the platform
  file's keys, `fixed` ones read only), quick toggles, system, then every module's options. `schema.test.nu` covers
  `Schema.js`.
- Options in `mod.nu` reach the shell as generated json beside the tree (`bar.json` the bar layout, `notify.json`,
  `pomodoro.json`, `clipboard.json`) and the `fx` section of `theme.json`; its other knobs stay in the repo copy.
- Colors come from `Colors.qml`/`Theme.qml` tokens, never hardcoded.
- No explanatory help sentences in the UI: short labels, values, key hints (`[ESC] Dismiss`) and terse empty states
  (`> NO TRAY ICONS`) only.
- Launcher prefixes: `=` calc, `>` run, `@` windows, `?` keys, `:` clipboard, and the capture modes `+` task, `!`
  reminder, `#` note (through `scripts/capture.nu`); `appsearch openWith '<text>'` opens it on a mode (SUPER+i,
  SUPER+SHIFT+i for `!`).
- Reminders (`scripts/reminder.nu`): transient wall-clock timers plus one record each in
  `$XDG_STATE_HOME/quickshell/reminders`, which `quickshell-reminders-rearm.service` re-arms after a reboot or logout.
- The tree (`config/`, paths above relative to it) is a managed copy: edit the repo, `dot apply desktop/quickshell`;
  `restart.nu` restarts the unit.
