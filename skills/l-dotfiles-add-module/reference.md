# add-module reference

Signatures are in `scripts/lib/module.nu`; read its doc comment above a helper before using a flag not shown here.

## Declarations

- Sources (`<src>`, `<file>`, `<script>`) are relative to the module dir: `config/...` for what is installed,
  `scripts/...` for what runs.
- Files: `file-copy <src> <dest> [--then]`, `files-into <dir> <src...>`, `file-text <dest> <text> [--generated]
  [--in-place]` (`--generated` outputs are rewritten without a drift check), `file-render <src> <dest> {KEY: v}`
  (`@KEY@`), `file-link` (only where the app reads the repo live), `link-commands <file...>`, `json-merge <file>
  [(json-set [k] v) (json-delete [k])]` (or a record of top-level keys), `ini-merge <file> {section: {key: v}}
  [--missing-only]`, `desktop-override <id> {|text| ...}` (with `desktop-set {Key: v}` inside), `desktop-exec <id>
  <cmd> [--command] [--args] [--env-vars]` (rewrites its `Exec=` lines), `shell-aliases <name>` (the module's
  `config/aliases.nu`/`config/aliases.zsh`; a tool's aliases live with the module declaring the tool, never in
  core/nushell or core/zsh).
- MCP: `mcp-servers {name: spec}` (Claude, Gemini, Copilot and Hermes, each in its format; null drops one),
  `mcp-command <name> <script>`, `mcp-uvx` (pinned PyPI server in its own venv), `mcp-npm <name> <dir> <prefix>`
  (`npm ci` on the committed lock).
- Rules: `udev-rules <src> [trigger args...] [--then]` (reloaded and triggered by `udev-reload [trigger args...]
  [--and <cmd>]`, also the `--then` of any other file udev reads), `polkit-rules <src> [--name] [--values {KEY: v}]`.
- Units: `unit-file <src> [--name] [--values {KEY: v}] [--enable --now]`, `unit-timer <name> <description> [--calendar]
  [--boot] [--startup] [--every] [--delay] [--accuracy] [--ac-power <udev rules>] [--enable --now]` (a calendar adds
  `Persistent=true`), `unit-enable|unit-disable|unit-mask <name> [--now]`, `unit-switch <name> <bool> [--now]`,
  `unit-restart <name> [--reload] [--if-running]` (the one `--then` for a unit; skips a unit not installed yet),
  `dropin <unit> <src> [--name] [--values]`, `user-hook <name> <script> --watch [paths] [--permanent] [--no-brake]
  [--mkdir]`.
- Groups: `group-system <group> [members]` (a sysusers.d file), `group-admins <group>` (wheel in it).
- Fetch: `fetch-file <url> <sha256> <dest> [--extract <member>]`, `fetch-git <url> <commit> <dir>`; both mark
  themselves `--network`.

## Actions

- `exec <name> [argv]` and `step <command> [args]` (an own export, run at apply time) are recorded with any of
  `--creates <path>`, `--key <string>` (reruns when the key changes: a version, a hash the module computes), `--done`
  (an eval-time "already so", `--done=($ref == $COMMIT)`) or `--undo [argv]`.
- `--undo` runs from the state dir, before the module's other actions, once the verb no longer returns the action: the
  module off or gone, but also a verb returning `[]` on a passing condition. So never leave an action with an undo out
  because secrets are locked. An undo whose command is gone counts as done.
- Name an action by its version and a bump replaces it, the old undo first:
  `exec $"flux-toolchain ($channel)" [...] --undo [rustup toolchain uninstall $channel]`.
- `--network`: offline (one HTTPS probe per run) or on the remote's 5xx, 429 or an unresolvable name, it is pending and
  reruns on the next apply. `--requires <path>`: pending while an earlier download's path is missing.
- Pending by hand: a step that cannot go on yet does `exit $EXIT_PENDING` with its reason as the last line
  (`programming/forgejo`); it is not recorded.
- Timeouts: an action and its process tree are killed after 20 min (`STEP_TIMEOUT`, `--timeout <duration>` for longer),
  a `--then` after 5 min, a verb's evaluation after 2 min.

## Reactions

A `--then` runs once per module run after every action, however many declarations carry the same argv; when it fails
it fails all of them, so they retry. `then-step <command> [args]` runs one of the module's own exports as the reaction
(a reload with its own checks, `desktop/hyprland`). `exec --then [argv]` runs after that exec went through.

## Helpers

`xdg config|data|cache|state|runtime ...parts`, `unit-dir`, `process-running <name>` (gate a reload in `theme`),
`group-exists <name>`, `package-version <pkg>` (upstream version without epoch and pkgrel, null when not installed),
`palette-load` (for `theme`), `recorded-hashes` (what dot last wrote per path), `SYSTEM_STATE`, `SYSTEM_REPO`.

## Option keys

`type`, `default`, `doc` required; `label`, `group`, `choices`, `min`/`max`/`step`, `apply` (default relink), `scope`
(default machine), `toggle` (set through `scripts/toggles/toggle-<name>.nu`: `on`/`off` for a bool, else
`set <value>`; its `get` is what the settings window shows; `l-dotfiles-toggles`).

## What root runs

Root runs a module's `system` verb and `packages` hook, and `detect` only of a module such a one names in `deps` or
`reads` (`modules-root-run` in `scripts/lib/modules.nu`). The root copy holds every `.nu` file but other files only of
root-run modules: a `system` verb reading another module's data file needs that module root-run.

## Drift and app state

- A managed file the app later edits is drift, kept until `dot module adopt <file>` (into the module) or
  `dot module reset <file>` (module copy back, edit preserved aside); `dot apply --force <group>/<module>` resets all.
- An app that saves over its copy (OBS, save-on-exit apps) needs a `backup` verb carrying the live file back (run by
  `dot sync`); strip theme output in it. Per-machine state (resolution, devices, logins) goes to
  `host-file <dir> <file>` (`<dir>/<host>/<file>`); `restore` reads `host-seed <dir> <file>` (own copy, else
  `<dir>/<file>`); a credential only `host-file`.
