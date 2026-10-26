# arch-dotfiles

Every machine and user setting is reproducible from this repo through `dot` (`scripts/dot.nu`, linked to
`~/.local/bin/dot`, ahead of graphviz's `dot`).

## Skills

| skill | for |
|---|---|
| `l-dotfiles-install` | installing a machine (owner, generic, WSL), the boot chain, another login |
| `l-dotfiles-add-module` | a new `configs/<group>/<module>/mod.nu`, verbs, options, running one module |
| `l-dotfiles-add-package` | packages in a module's meta, the mirror, removal, supply-chain pins |
| `l-dotfiles-apparmor-profile` | profiles, `local/` rules, denials, enforce policy |
| `l-dotfiles-theming` | wallust templates, theme switches dark and light |
| `l-dotfiles-toggles` | `scripts/toggles/toggle-*.nu` and its quickshell wiring |
| `l-dotfiles-quickshell-dev` | bar and shell: reload, logs, IPC, screenshots |
| `l-dotfiles-vm-test` | `dot test run`, the multi-hour VM test |
| `l-dotfiles-secrets-access` | secrets, YubiKey unlock, adding a secret |
| `l-dotfiles-platform-facts` | `platforms/` facts vs `profiles/` capabilities vs options |
| `l-dotfiles-gui-testing` | launching an app only to check it: the headless output |
| `l-dotfiles-live-debug` | status, run logs, journals, changed files, denials, who wrote a file |
| `l-dotfiles-streaming` | OBS, the bar's obs widget, Spotify and Discord inspection |
| `l-homelab` | homelab services, reaching them, their secrets, requesting lab changes |

`skills/mod.nu` links every `skills/l-*` into each agent's skill dir; a new one appears after
`dot apply skills programming/hermes`.

## Commands

- `dot test lint` (about a minute, no root): repo rules plus every `*.test.nu`/`*.test.sh`. `dot test check`:
  formatters and linters. `dot test run`: the VM test.
- `dot apply [mod...] [--user|--system] [--packages] [--force]`, `dot plan [mod...] [--system] [--order|--modules]`,
  `dot status [--brief|--json]`, `dot set [mod[.key] [value]] [--default] [--machine] [--json]`,
  `dot module adopt|reset|unlink|remove|restore`, `dot explain <path|package>`, `dot log [--trace]`.
- `dot internal <cmd>` (`scripts/lib/internal.nu`): plumbing for scripts and units; `gen` regenerates
  `mirror/packages.txt` (lint fails when stale), `iso` builds the install iso.
- Agents never reach root: run dot with `DOT_SYSTEM=skip` (or `--no-system`); a system part is then pending (exit 3).
  sudo and pkexec take a YubiKey touch or fingerprint on Luca's side, the password as fallback.
- `dot sync` (pull, migrate, install, apply, back up, signed `Generation: <n>` commit, push) is Luca's only commit
  path: agents never commit, push or run it, `--no-push` included.
- `collect-diagnostics [dest]`: bash only, runs from a USB stick; hardware, boot, journals, dot state.

## Layout

- `configs/<group>/<module>/mod.nu`: one tool or task. Read the group's `AGENTS.md` before editing there (one
  instruction file per directory, no `CLAUDE.md`; `configs/programming/claude/CLAUDE.md` is the global `~/.claude`
  file). `dependencies.txt` names the groups a group reaches into.
- `platforms/<name>.nuon` (facts, groups) and `<name>.options.nuon`: `luca-pc`, `luca-notebook`, `server`, `vm`,
  `wsl`. `profiles/<name>.nuon`: user capabilities (`luca`, or `custom` for none).
- `migrations/<NNNN>-<slug>.nu`: one-time `up` changes; fresh installs mark existing ones as run.
- `scripts/` (commands in `~/.local/bin`), `scripts/lib/` (the engine: `module.nu` API, `pipeline.nu` run,
  `converge.nu` plan/apply, `system-apply.nu` root entry), `scripts/toggles/`.
- `configs/secrets/`: private submodule, pulled only with the `secrets` profile. `keys/` is git-crypt (credentials),
  `state/` plaintext app state, plus the owner's own modules (applied last, packages kept off the mirror).
- `mirror/`: own pkgbuilds, `overrides.conf`, `iso/` (the install iso; only its stub `lsck0-install` is frozen on a
  stick).

## Conventions

- Everything reproducible through `dot`; nothing set by hand.
- User layer (`link`) never uses sudo and may read user facts; system layer (`system`) runs as root from the root copy
  `/var/lib/dotfiles/repo` and never reads user facts. Lint enforces both.
- Machine facts in the platform (`platform-has`), the one user capability in the profile (`profile-has secrets`),
  settings in typed options. Never gate on a username.
- Modules declare what they want (`scripts/lib/module.nu`); the engine applies the difference. Managed files are copies
  with their hash recorded; a changed copy is kept until `dot module adopt` or `reset`; files dot never wrote are taken
  over; both preserved aside. Links only where an app reads the repo live. Nothing is written into `~/sync`.
- Keep `$HOME` clean: env var to `configs/base/xdg/app-dirs.conf`, hardcoded dirs to `RECLAIM` in
  `configs/base/xdg/mod.nu`, forced non-dot dirs to `home.hidden`.
- Native over bolt-on: the tool's own mechanism (Hyprland rules, systemd units, pipewire config, pacman hooks, udev),
  never a wrapper or polling script.
- One extension pattern: a new capability is a new file following the convention (module, option, package, migration,
  toggle, theme, profile); adding the file is the whole change.
- `dot` manages this machine only.

## Backups

One home per kind of data, no catch-all: config in git; app state in `configs/secrets/keys/<app>/` (logins, tokens) or
`state/<app>/`, restored by the module; shared live data in `~/sync`; work in its own git remotes.

## Gotchas

- `FAILURES.*` at the root: what failed in the last run. `dot log [run] [--trace]`; a crash leaves
  `<state>/crash.json`.
- State: `~/.local/state/dotfiles` (root: `/var/lib/dotfiles`); `modules/<id>/<verb>.nuon` is the one record of what
  dot wrote; `ledger` holds units, packages, migrations.
- Locked secrets start with `\0GITCRYPT` (`secret-is-plaintext`); never write into `configs/secrets/` while locked.
- Hyprland config and dispatch are Lua: `hyprctl dispatch "hl.dsp.exec_cmd('cmd')"`.
- `~/.config/<app>` holds managed copies: a repo edit changes nothing until `dot apply <group>/<module>`.
  `file-text --generated` outputs are rewritten every run; `dot explain <path>` names the writer.
- GUI testing stays on the agent's own headless output (`l-dotfiles-gui-testing`).
- X11 apps scale through `GDK_SCALE` only; no `Xft.dpi`.
- A module runs only when its group is in the platform's `groups` and its `enable` option is true.
