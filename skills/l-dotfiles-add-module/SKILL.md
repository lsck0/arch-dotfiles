---
name: l-dotfiles-add-module
description: Writing a configs/<group>/<module>/mod.nu (meta with deps and packages, typed options, the fixed verbs, declarations and helpers), how dot picks it up, and running it alone. Load when adding, porting or restructuring a module, or when a new program, service or setting needs a home in the dotfiles.
---

# add-module

A module is one folder `configs/<group>/<module>/` with a `mod.nu`. Nothing central changes: `dot` discovers its verbs,
options and packages.

An owner-only module (employer setup, bookmarks, key wiring) goes in the private submodule:
`configs/secrets/<module>/mod.nu`, id `secrets/<module>`. Same contract; runs after every other group wherever the
submodule is pulled (gate inside: `owner-unlocked`, or `profile-has secrets` for a non-personal capability, in `link`,
`$env.FORM_FACTOR` in `system`); plaintext code; packages stay out of `mirror/packages.txt` (a mirror package it needs
goes in the platform's `extra_packages`).

## The contract

```nu
use module.nu *

export const meta = {
    deps: [core/gh]                                   # modules that apply first, any group
    reads: [base/ssh]                                 # options in cfg.deps only: no order, never waits on it
    packages: {pacman: [btop], native: [], flatpak: {}, nix: []}  # their installed versions are in the input hash
    serial: false                                     # true: runs alone (rustup, a package manager)
    inputs: [configs/secrets/state/repositories]      # more input-hash files (never its own package's binary)
    volatile: false                                   # true: always evaluated (reads machine state)
    backup: {secrets: true}                           # its backup verb writes into secrets: runs only unlocked
    secrets: ["alloy-{host}"]                         # what its system verb reads of keys/ (root gets only these)
    phase: early                                      # install stage: early (base/pacman) or install (base/yubikey)
    barrier: {run: boot-commit, watch: [/etc/x]}      # an export run once after a layer's apply that changed a
                                                      # watched path or a decl's --notify <this id> flagged
}

export const options = {
    accent: {
        type: string                                  # nu type name; list<string>, int, bool, string? ...
        default: c4
        doc: "Palette slot for titles and the selection"
        label: "Accent colour"                        # the settings UI's; group, choices, min/max/step too
        choices: [c1 c2 c3 c4 c5 c6]
        apply: live                                   # live (needs an apply verb or toggle) | relink | relogin | reboot
        scope: user                                   # default machine (platform only); user: the profile may set it
    }
}

# user layer: declarations of what it wants, nothing written here
export def link [cfg: record] {
    [
        (files-into (xdg config btop) btop.conf)
        (unit-file oom-notify.service --enable --now)
    ]
}

# root, from the root-owned copy; never a user fact
export def system [cfg: record] {
    file-copy smartd.conf /etc/smartd.conf --then (unit-restart smartd.service --if-running)
}

export def theme [cfg: record, wallpaper: string] {
    let p = palette-load
    if $p == null { return [] }
    file-text (xdg config btop themes pywal.theme) $"theme[title]=\"($p | get $cfg.accent)\"\n" --generated
}

# a live option's hook: dot set calls it after the value changed
export def apply [cfg: record] {
    theme $cfg ""
}

# hook: values for options left null by platform and profile (hardware, live state), run before resolving
export def detect [cfg: record]: nothing -> record {
    {accent: (if (gpu-list | is-empty) { "c2" } else { null })}
}

# hook: packages that depend on an option, merged into meta.packages
export def packages [cfg: record]: nothing -> record {
    {pacman: (if $cfg.accent == "c4" { [btop-extra] } else { [] })}
}
```

- Verbs (`VERBS` in `scripts/lib/modules.nu`): `link`, `system`, `theme`, `apply`, `backup`, `restore`, `update` (what
  floats outside pacman, run by `dot sync`). Any other export is a `step` target or a name another module imports;
  everything else is a plain `def` (lint checks). A helper a unit, toggle or keybind runs is a script in the module
  dir, installed with `link-commands` or `files-into`. A linked one finds the repo with `const REPO = path self |
  path expand | path dirname --num-levels <depth>` (expanded first: `path self` and a relative `use` resolve against
  the `~/.local/bin` link; lint: `LINKED_RELATIVE` in `scripts/lib/gate.nu`); every other file writes `path self`
  with a relative path, one `..` per level (`path self ../../..` in a module dir, `path self .` for its own dir).
- Each verb takes the resolved options (`enable` always present) and returns declarations, nested to any depth (null
  and `[]` add nothing). An optional one in the returned list is `(if <cond> { decl })`, never `else { [] }` or a
  trailing `| compact`; a value other code consumes (`++`, `append`, a spread) still needs its `else`.
- A disabled module (option off, group gone) declares nothing on the next full run, so its files, links and units go,
  each json key it merged goes back to what it held before dot set it (unless edited since),
  and each recorded `exec` or `step` runs its `--undo`. A plain one (no `--creates`, `--key`, `--done` or `--undo`) is
  not recorded: it runs on every evaluation and what it did stays.
- Hooks (`HOOKS`): `detect` fills options platform and profile left null (a failure only warns); `packages` adds a
  `{pacman, native, flatpak, nix}` part.
- Declarations (`scripts/lib/module.nu`):
  - files: `file-copy <src> <dest> [--then]`, `files-into <dir> <src...>`, `file-text <dest> <text> [--generated]
    [--in-place]`, `file-render <src> <dest> {KEY: v}` (`@KEY@`), `file-link` (only where the app reads the repo
    live), `link-commands <file...>`, `json-merge <file> [(json-set [k] v) (json-delete [k])]`, `ini-merge <file>
    {section: {key: v}} [--missing-only]`, `desktop-override <id> {|text| ...}`, `mcp-servers {name: spec}`
    (Claude, Gemini, Copilot and Hermes, each in its format; null drops one), `mcp-uvx` (a pinned uvx server and its
    prefetch), `shell-aliases <name>` (the module's `aliases.nu`/`aliases.zsh` into nushell's autoload dir and zsh's
    conf.d; a tool's aliases and defs live with the module declaring the tool, never in core/nushell or core/zsh).
  - rules: `udev-rules <src> [trigger args...] [--then]` (into `/etc/udev/rules.d`, reloaded and triggered by
    `udev-reload [trigger args...] [--and <cmd>]`, also the `--then` of any other file udev reads), `polkit-rules
    <src> [--name] [--values {KEY: v}]` (into `/etc/polkit-1/rules.d`, rendered when given values).
  - units: `unit-file <src> [--enable --now]`, `unit-enable|unit-disable|unit-mask <name> [--now]`,
    `unit-restart <name> [--reload] [--if-running]` (the one `--then` for a unit: skips a unit not installed yet;
    `--if-running` leaves a stopped one stopped), `dropin <unit> <src> [--name]`,
    `user-hook <name> <script> --watch [paths] [--permanent] [--no-brake] [--mkdir]`.
  - actions: `exec <name> [argv]`, `step <command> [args]` (an own export, run at apply time). Either is recorded
    with any of `--creates <path>`, `--key <string>` (it runs again when the key differs from the one it last ran
    with: a version, a hash the module already computes), `--done` (an eval-time "already so", e.g.
    `--done=($ref == $COMMIT)`) or `--undo [argv]` (run from the state dir, before the module's other actions, once
    the verb no longer returns it: the module off or gone, but also a verb that returns `[]` on a passing condition,
    so an action with an undo is never left out on secrets locked; an undo whose command is gone counts as done).
    Never a stamp file of its own. Name an action by its version
    (`exec $"flux-toolchain ($channel)" ... --undo [rustup toolchain uninstall $channel]`) and a bump replaces it: the
    old name's undo runs first. `exec --then [argv]` runs after it went through.
  - reactions: a `--then` runs once per module run after every action, however many declarations carry the same
    argv; it fails all of them when it fails, so they retry. `then-step <command> [args]` is the argv running one of the
    module's own exports, for a reload with its own checks (`desktop/hyprland`).
  - pending: a step that cannot go on yet (a remote not reachable) `exit $EXIT_PENDING` with its reason as the last
    line; it is not recorded and runs on the next apply (`programming/forgejo`).
  - other: `fetch-file <url> <sha256> <dest> [--extract <member>]`, `fetch-git <url> <commit> <dir>`,
    `group-system <group> [members]` (a sysusers.d file), `group-admins <group>` (wheel in it), `palette-load` (for
    `theme`). An exec or step that downloads takes `--network`: offline (an HTTPS probe as the
    user, once per run), or failing on the remote's 5xx, 429 or an unresolvable name, it is pending and runs on the
    next apply; fetch-* mark themselves. One that builds on an earlier download takes `--requires <path>` (the fetched
    tree, the image): while the path is missing it is pending instead of failing. Each is killed with its
    whole tree after 20min (`--timeout <duration>` for longer), a `--then` after 5min, a verb's evaluation after 2min.
- Evaluation never touches the network: a verb or hook only reads local state; downloads go in a step or exec.
- A mod.nu takes the engine from module.nu only (lint: `ENGINE_INTERNAL` in `scripts/lib/gate.nu`); it also exports
  `recorded-hashes` (what dot last wrote per path) and the root's `SYSTEM_STATE`/`SYSTEM_REPO`. A module reading
  another's options names it in `meta.reads` (no ordering) or `meta.deps` (runs after it, theme pass included).
- Helpers: `xdg config|data|cache|state|runtime ...parts`, `unit-dir`, `process-running <name>` (gate a reload in
  `theme`), `group-exists <name>`, `package-version <pkg>` (upstream version without epoch and pkgrel, null when not
  installed), `desktop-set {Key: v}` (in a `desktop-override` closure; sets or adds the key in `[Desktop Entry]`). The
  user layer already has `configs/base/xdg/app-dirs.conf` loaded; don't copy those variables into a module.
- Option keys: `type`, `default`, `doc` required; `label`, `group`, `choices`, `min`/`max`/`step`, `apply` (default
  relink), `scope` (default machine), `toggle` (set through `scripts/toggles/toggle-<name>.nu`: `on`/`off` for a
  bool, else `set <value>`; its `get` is what the settings window shows).
- Facts: `platform-has homelab|wireguard|secure_boot_own_keys|lsck0_snapshot` (`PLATFORM_FACTS`), `$env.FORM_FACTOR`
  (`desktop laptop server vm wsl`), `owner-unlocked` and `profile-has secrets` (link only); which to use:
  `l-dotfiles-platform-facts`. Settings are options: `dot set <group/module>.<key> <value> [--machine]`.
- A file the app later edits is drift: kept until `dot module adopt <file>` (into the module) or `dot module reset
  <file>` (module's copy back, edit preserved aside); `dot apply --force <group>/<module>` resets all.
- One-time change on installed machines: `migrations/<NNNN>-<slug>.nu` from `0000-sample.nu` (`up` only;
  `export const layer = "system"` runs as root). Fresh installs mark all as run, so a migration never replaces a
  declaration.
- Root runs the `system` verb and `packages` hook of a module, and `detect` only of a module such a one names in
  `deps` or `reads` (`modules-root-run` in `scripts/lib/modules.nu`). The root copy holds every `.nu` file but the
  other files only of those modules: a `system` verb reading another module's data file needs that module root-run.
- A deleted module's dir needs no unlink first: the next full `dot apply` removes what its state recorded.
- An app that saves over its copy (OBS, save-on-exit apps) needs a `backup` verb carrying the live file back (run by
  `dot sync`). Per-machine state (resolution, devices, logins) goes to `host-file <dir> <file>`
  (`<dir>/<host>/<file>`); restore reads `host-seed <dir> <file>` (own copy, else `<dir>/<file>`), a credential only
  `host-file`. Strip theme output in the backup.

## Run it alone

```bash
dot plan <group>/<module>          # actions; empty after the apply
dot apply <group>/<module>         # its user layer; a second run is a no-op
dot module unlink <group>/<module> # reverse it
dot plan --system <group>/<module> # the system verb, planned as the user
dot test lint                      # refs, layer rules, the module's *.test.nu
dot test check                     # formatters, linters, nu parse gate
```

`dot log --trace` shows timing, `dot explain <path>` the writer.
