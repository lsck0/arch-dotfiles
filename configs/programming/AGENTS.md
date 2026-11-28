# programming

- Toolchains install eagerly in `link` (`exec ... --creates` or a plan-time check), so the first build or LSP start
  works offline; never lazily on first launch.
- A package goes into the module that uses it, else the closest catch-all: the package-only `toolchains`, `python`,
  `security`, `http` and `infra`, or `vcs` and `devtools`, which also carry config.
- Formatter configs live in `programming/formatting` and are passed by nvim's conform (from the repo) and Doom's
  apheleia (from copies in `~/.config/doom/formatting`) as the fallback when a project has none, never linked. The
  exception is latexindent and chktex: they and texlab find their configs by path, so those are copied into
  `~/.config`.
- Emacs is Doom: a pinned checkout in `~/.config/emacs`, the repo's `config/doom/` files copied to `~/.config/doom`, and
  `doom sync` as a step keyed on the pin, `init.el`, `packages.el` and the emacs package. `init.el` stays Doom's
  default apart from the enabled modules; own settings go in `config.el`. The theme verb writes a palette theme and
  the font into the wal cache and reloads a running emacs over emacsclient.
- Owner-only modules (`bugwarrior`, `jai`, `projects`) gate on `owner-unlocked` (`l-dotfiles-secrets-access`).
  `projects` runs after `core/gh`.
- Telemetry off for every agent and editor. One exception, opt-in per machine: `programming/claude`'s
  `remote_control` option, since remote control needs the feature flags that `DO_NOT_TRACK` and `DISABLE_TELEMETRY`
  switch off; on, both are lifted for claude alone. An agent that asks for consent at its first prompt gets the
  answer declared (`programming/hermes` `SETTINGS`), or its unattended sessions hang on the dialog.
- `programming/claude` denies the agent's file tools the credentials (`SECRET_READS_*`: `configs/secrets/keys`, the
  git-crypt key, ssh and gpg keys, tool tokens). A module still reads its secret in its own code; an agent works with
  the names (`l-dotfiles-secrets-access`).
- `programming/claude` themes Claude Desktop through its own mod, `config/mods/wallust-look`: copied to
  `$XDG_DATA_HOME/claude/mods/wallust-look`, loaded by every session through `CLAUDE_CODE_PLUGIN_DIRS`, and painted at
  session start from the `palette.json` the theme verb writes beside it. `look.test.nu` checks every theme paints.
- Editors in use are nvim, Doom Emacs and Zed. VSCodium (vim keys, theme, settings) and JetBrains (toolbox only) are
  backups: no language extensions, LSPs or theme parity are owed to them.
- `offload` (platform fact `offload`: `target` luca-pc, `client` luca-notebook) sends the repo's HEAD and working
  changes as a git ref to a per-client bare repo on the target and runs the command there in a transient unit under a
  sleep inhibitor, so the target sleeps again after; `offload host` is its ssh-called half; the target's address is
  `base/ssh.wake_host`. On the target `worker.nu` (installed to `/usr/local/lib/offload`) is the one protocol every
  client goes through: offer, submit (job JSON; stdin a header line, a streamed image archive pinned by its id, the
  commit's pack, shallow), status, get, cancel, gc, with a per-repo cache keyed by the worker; the lab's
  builder reaches it as the locked-down `labworker` (key and address from `HOMELAB.builder`, forced command `serve`),
  Luca's devices as Luca (`offload worker`, and `offload host start` admits through it). Admission is idle-only
  (`gate.nu`: gamemode, obs output; power) and per-device consent (`consent.nu`'s notification, trusted devices
  revoked from the bar's homelab panel); jobs run in `offload.slice` and `offload-enforce.path` cancels them when the
  desktop gets busy.
