# desktop/quickshell

Editing, reload, logs, screenshots: `l-dotfiles-quickshell-dev`.

- `shell.qml`: one `Bar` per screen, loads `plugins/Plugins.js` (summon ids and bar layout), owns the `shell` and
  `discord` IPC targets; every other target lives in the plugin or `Commons/` singleton it drives.
- `plugins/<feature>/`, `Commons/` (singletons: palette, style, audio, tasks, timers), `Ui/` (shared widgets),
  `scripts/` (helpers the plugins call), `services/` (`AppLibrary`, `AppSearch`), `shaders/` (baked by `restart.nu
  prepare`), `sounds/`.
- IPC: `quickshell ipc -p ~/.config/quickshell show` lists every target; panels open with
  `quickshell ipc call shell summon <id> [json]` or `quickshell ipc call bar open <panel>`.
- Colors come from `Colors.qml`/`Theme.qml` tokens, never hardcoded.
- The tree is a managed copy: edit the repo, `dot apply desktop/quickshell`; `restart.nu` restarts the unit.
