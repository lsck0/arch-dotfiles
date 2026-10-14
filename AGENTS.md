# arch-dotfiles

Arch Linux system setup: every machine and user setting is reproducible from this repo through one command, `dot`
(`scripts/dot.nu`, `~/.local/bin/dot`; ahead of graphviz's `/usr/bin/dot` on PATH).

## Skills

Load the skill a task needs from `skills/<name>/SKILL.md`.

| skill | use it for |
|---|---|
| `l-dotfiles-install` | installing a machine (owner, generic, WSL), the boot chain, adding another login |
| `l-dotfiles-add-module` | a new `configs/<group>/<module>/mod.nu` (verbs, options, packages), running one module alone |
| `l-dotfiles-add-package` | adding or removing a package in a module's meta (or a group's `packages.txt` until ported) |
| `l-dotfiles-apparmor-profile` | writing or adjusting a profile or `local/` rule, reading denials, enforce policy |
| `l-dotfiles-theming` | adding a wallust template or generator, testing a theme switch dark and light |
| `l-dotfiles-toggles` | adding a `scripts/toggles/toggle-*.nu` and wiring it into quickshell |
| `l-dotfiles-quickshell-dev` | editing the bar/shell, reload, logs, IPC, screenshots |
| `l-dotfiles-vm-test` | the end-to-end VM test, `dot test run` (hours) |
| `l-dotfiles-secrets-access` | where secrets live, unlocking with the YubiKey, adding a secret |
| `l-dotfiles-platform-facts` | machine facts in `platforms/` vs user capabilities in `profiles/`, adding a fact |

Every `skills/l-*` is global, linked into each agent's skills dir by `skills/mod.nu`: `l-dotfiles` (the repo overview)
and the `l-dotfiles-*` above cover the dotfiles and system configuration, the other `l-*` are Luca's style guides,
personas and workflows.

## Commands

- `dot test lint`: static checks (module refs, layer rules, `~/sync` writes) plus every `configs/**/*.test.sh`;
  about 12 s, no root. `dot test run` is the multi-hour VM test.
- `configs/base/apparmor/apparmor.test.nu`: profiles.conf policy and a compile of every own profile and `local/`
  drop-in; the "Failed to create cache" warnings are expected without root.
- `dot gen`: regenerates `mirror/packages.txt`; `dot test lint` fails when it drifts.
- `dot update`: pull, snapshot, migrate, install, apply; the one command a person runs. `dot --help` lists the rest.
- `dot plan [mod...] [--system] [--sandbox]`: what an apply would do (actions per module, drift, pending migrations,
  undeclared packages); `--sandbox` adds the write set of a real run under bubblewrap. Touches nothing.
- `dot link [mod...]`: the user layer, incremental; `dot apply` is the system layer for a wheel user, then the user
  layer; `dot system` the system layer alone; `dot install` every declared package, flatpak and nix, then convergence.
- `dot unlink <mod>` / `dot remove <mod>`, `dot options [mod] [--json]`, `dot set|unset <mod>.<key>`, `dot watch`,
  `dot diff`, `dot adopt <file>`, `dot explain <path|package>`, `dot status`, `dot log [--trace]`, `dot gen`.
- Agents never reach root: run `dot` with `DOT_SYSTEM=skip` (or `--no-system`); a system part is then recorded as
  pending (exit 3). A sudo or pkexec prompt goes through pam_u2f first: a YubiKey touch (or an enrolled finger) on
  Luca's side, the password as the fallback.
- `dot sync`: backs up live app state, makes the signed `Generation: <n>` commit and pushes. The user's
  only commit path; agents never commit, push or run it.

## Layout

- `configs/<group>/<module>/`: one tool or task; `mod.nu` (meta incl. packages, options, verbs; skill
  `l-dotfiles-add-module`); optional `*.test.{nu,sh}`. Groups: base, core, fonts, desktop, socials, latex, qemu,
  creating, gaming, programming, llm, rocm, pentesting. `dependencies.txt` names the groups a group reaches into.
- `platforms/<host>.nuon`: machine facts and groups; `<host>.options.nuon` its option values. `profiles/<user>.nuon`:
  user capabilities, copied to `~/.config/dotfiles/profile.nuon` by bootstrap and `adduser-dotfiles`. A platform's
  `extra_packages` also land in `mirror/packages.txt`, the mirror's build list.
- `migrations/<NNNN>-<slug>.nu`: one-time structural changes (`up`, `down`), run once per machine by `dot update`.
- `scripts/`: commands linked into `~/.local/bin`; `scripts/lib/*.nu` the engine (`module.nu` the module API,
  `pipeline.nu` the run, `converge.nu` plan and apply, `system-apply.nu` root's one entry, `system.nu` the root copy).
- `scripts/toggles/`: on/off switches, `status.nu` (JSON of all), `menu.nu`.
- `configs/core/wallust/` (templates, `palette.nu`), `configs/core/themes/*.json`, `dot theme [set|random|get|list]`;
  each module themes its own program in its `theme` verb, run by `dot theme apply`.
- `configs/desktop/quickshell/` (bar, launcher, lock, notifications), `configs/desktop/hyprland/` (Lua config).
- `secrets/`: git-crypt submodule. `mirror/`: own pkgbuilds and `overrides.conf` for the `[lsck0]` package mirror.
- `bootstrap.sh` (from the ISO: nushell and a verified checkout, then `dot bootstrap`), `dot stage` (one unattended
  stage per boot), `dot test` (lint, check, the VM test).

## Conventions

- Commits are `Generation: <n>` from `dot sync` only, not conventional commits. Never commit or push.
- Every setting must be reproducible through `dot` on a fresh system; nothing set by hand.
- The user layer (`link` verb) never uses sudo and may read user facts (`profile-has`, `$nu.home-dir`);
  the system layer (`system` verb) runs as root and never reads a user fact. `dot test lint` enforces
  both, for mod.nu verb by verb.
- The system layer runs from the root-owned copy `/var/lib/dotfiles/repo`: `dot apply`/`install` pack tracked and
  untracked files with the system secrets into one archive for `system-apply.nu apply` (the one command sudo or the
  polkit action runs); root never executes the user's checkout.
- Machine facts live in the platform file (`platform-has`), user capabilities in the profile (`profile-has
  secrets|identity|homelab|work`), per-module settings in typed options. Never gate on a username.
- A module declares what it wants (`scripts/lib/module.nu`: `file-copy`, `files-into`, `file-text`, `file-render`,
  `file-link`, `link-commands`, `json-merge`, `unit-file`, `unit-enable`, `dropin`, `desktop-override`, `exec`); the
  engine applies the difference. Managed files are real copies with their hash recorded; a file changed since its
  last apply is drift, kept until `dot adopt` or `--force`; a file the dotfiles never wrote is taken over; both are
  preserved aside. Links only where an app must read the repo live (`file-link`, the `~/.local/bin` commands).
  Nothing is written into `~/sync`.
- `packages.txt` (until ported): one package per line, alphabetical, comment column aligned at column 35.
- Keep `$HOME` clean: a program that would litter `~/.<name>` is pointed under the XDG base dirs in the same change
  that adds it. If it reads an env var (`FOO_HOME`, `XDG_*`), add that var to `configs/base/xdg/app-dirs.conf`
  (grouped, commented; state/runtime to `.local/state`, data to `.local/share`, config to `.config`, caches to
  `.cache`); if it hardcodes `~/.<name>`, add a row to `const RECLAIM` in `configs/base/xdg/mod.nu`. Running
  tools, shell startup files and credential stores (`.ssh`, `.gnupg`, `.pgpass`, `.kube`, `.pulse-cookie`) stay in
  `$HOME`; a non-dot dir a tool forces into `$HOME` goes in `configs/base/xdg/home.hidden`.
- Modules run in dependency order: a group after base and the groups in its `dependencies.txt` (programming/projects
  needs core/gh), a module after its meta `deps` (or the siblings in its own `dependencies.txt`); every module whose
  dependencies finished runs at once (`DOTFILES_JOBS`, 1 = serial), `serial: true` alone.
  `dot plan` previews.
- Native over bolt-on: solve each thing with the framework's own mechanism (Hyprland window/workspace rules,
  systemd units and drop-ins, pipewire/wireplumber config, pacman hooks, udev rules, the `module.nu` declarations), not a
  wrapper or a polling script that reimplements what the tool already does. A solution that fights its tool is wrong.
- `dot` manages this machine only: nothing in other repos, no per-project hooks or shells it would need.
- One extension pattern, same for human and agent: a new capability is a file that follows the established
  convention (a `configs/<group>/<module>/mod.nu`, an entry in its `options` or `meta.packages`, a
  `migrations/<NNNN>-<slug>.nu`, a `scripts/toggles/toggle-*.nu`, a `themes/*.json`, a `profiles/<user>.nuon`),
  discoverable from this file and the skills. No special-case wiring: adding the file is the whole change.

## Backup model

Each kind of data has one home; borg is the last resort, never the first.

- Config and reproducible settings: this repo (git), app state as git-crypt `secrets/<app>/` restored by a module's
  `link` or `restore` verb.
- Anything meant to sync across devices or to the NAS: `~/sync` (syncthing). Primary for live, shared data.
- borg (`configs/core/borg`): the worst-case fallback for `$HOME` data that is NOT already covered, e.g. local
  work under `~/projects` not yet pushed, app state not in `secrets/` or `~/sync`. It excludes everything already
  safe elsewhere: `~/sync` (on the NAS), caches, toolchains, models, re-downloadable game/VM data. When a new
  backup is added, route the data to sync or git-crypt first and keep borg's excludes in step so nothing is stored
  twice.

## Gotchas

- `FAILURES.config` / `FAILURES.install` at the root list what failed in the last run (system failures included);
  `install.log` / `config.log` keep the terminal output (`.log` and `FAILURES*` are gitignored);
  every run's structured log and span tree is `dot log [run] [--trace]`, a crash leaves `<state>/crash.json`.
- dot's state: `~/.local/state/dotfiles` (root's `/var/lib/dotfiles`): `modules/<id>/<verb>.nuon` what each native
  module owns (input hash, outputs), `written`, `ledger`, `runs/`, `preserved/`.
- Locked secrets are git-crypt blobs starting with `\0GITCRYPT`; check with `secret-is-plaintext`, never write
  into `secrets/` while locked.
- A theme switch writes generated files through repo symlinks (VSCodium `settings.json`, herdr `config.toml`,
  spicetify `color.ini`, KDE colors), so it dirties the working tree.
- AppArmor: everything that opens other people's content stays `enforce` in `profiles.conf`;
  `apparmor.test.sh` fails otherwise. Use `aa complain <profile>` on one machine, not the baseline.
- Hyprland config is Lua (`hl.*`). Dispatch is Lua too: `hyprctl dispatch "hl.dsp.exec_cmd('cmd')"`,
  `hyprctl dispatch "hl.dsp.focus({ workspace = 3 })"`; the old `hyprctl dispatch exec cmd` fails.
- Background GUI testing stays off the user's screen. When an agent launches an app, game or editor only to
  screenshot or check it (not because the user is watching that task), put the window on a headless output the
  user never sees, not on a visible workspace: `hyprctl output create headless` (gives its own `HEADLESS-N`),
  launch/move the window onto that output's workspace (`focusmonitor HEADLESS-N` then launch, or
  `movetoworkspacesilent`), `grim -o HEADLESS-N` to capture, then `hyprctl output remove HEADLESS-N`. Each agent
  makes and removes its own; many can run at once without taking over the physical monitors. Use a visible
  workspace only when the user is directly working on that task.
- `xwayland.force_zero_scaling = true`: X11 apps scale through `GDK_SCALE`/`QT_AUTO_SCREEN_SCALE_FACTOR` (1 on a
  laptop, else 2); Java apps get the same value from `display-xwayland-scale` (`platform.nu`).
- A module runs only when its group is in the platform's `groups` and its `enable` option is true.
