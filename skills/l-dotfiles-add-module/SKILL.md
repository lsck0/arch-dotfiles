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
    packages: {pacman: [btop], native: [], flatpak: {}, nix: []}
    serial: false                                     # true: runs alone (rustup, a package manager)
    inputs: [configs/secrets/state/repositories /usr/bin/cargo-kani] # more input-hash files: relative is the repo's, ~ and / as is
    volatile: false                                   # true: always evaluated (reads machine state)
}

export const options = {
    accent: {
        type: string                                  # nu type name; list<string>, int, bool, string? ...
        default: c4
        doc: "Palette slot for titles and the selection"
        label: "Accent colour"                        # the settings UI's; group, choices, min/max/step too
        choices: [c1 c2 c3 c4 c5 c6]
        apply: live                                   # live | relink | relogin | reboot
        scope: user                                   # default machine (the platform only); user: the profile may set it
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
    file-copy smartd.conf /etc/smartd.conf --then [systemctl try-restart smartd.service]
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
  dir, installed with `link-commands` or `files-into`.
- Each verb takes the resolved options (`enable` always present) and returns declarations (nested lists fine).
- A disabled module (option off, group gone) declares nothing on the next full run, so its files, links and units go.
  What a `step` or `exec` did is not recorded and stays: declare anything that must go with the module.
- Hooks (`HOOKS`): `detect` fills options platform and profile left null (a failure only warns); `packages` adds a
  `{pacman, native, flatpak, nix}` part.
- Declarations (`scripts/lib/module.nu`):
  - files: `file-copy <src> <dest> [--then]`, `files-into <dir> <src...>`, `file-text <dest> <text> [--generated]
    [--in-place]`, `file-render <src> <dest> {KEY: v}` (`@KEY@`), `file-link` (only where the app reads the repo
    live), `link-commands <file...>`, `json-merge <file> [(json-set [k] v) (json-delete [k])]`, `ini-merge <file>
    {section: {key: v}} [--missing-only]`, `desktop-override <id> {|text| ...}`, `mcp-servers {name: spec}`
    (`~/.claude.json`; null drops one).
  - units: `unit-file <src> [--enable --now]`, `unit-enable|unit-disable|unit-mask <name> [--now]`,
    `unit-restart <name> [--reload]` (a `--then` that skips a unit not installed yet), `dropin <unit> <src> [--name]`,
    `user-hook <name> <script> --watch [paths] [--permanent] [--no-brake] [--mkdir]`.
  - other: `exec <name> [argv] [--creates path]`, `step <command> [args]` (an own export, run at apply time),
    `fetch-file <url> <sha256> <dest> [--extract <member>]`, `fetch-git <url> <commit> <dir>`, `group-admins <group>`,
    `palette-load` (for `theme`).
- Helpers: `xdg config|data|cache|state ...parts`, `unit-dir`, `process-running <name>` (gate a reload in `theme`),
  `desktop-set {Key: v}` (in a `desktop-override` closure). The user layer already has `configs/base/xdg/app-dirs.conf`
  loaded; don't copy those variables into a module.
- Option keys: `type`, `default`, `doc` required; `label`, `group`, `choices`, `min`/`max`/`step`, `apply` (default
  relink), `scope` (default machine), `toggle` (set through `scripts/toggles/toggle-<name>.nu`: `on`/`off` for a
  bool, else `set <value>`; its `get` is what the settings window shows).
- Facts: `platform-has homelab|wireguard|secure_boot_own_keys|lsck0_snapshot` (`PLATFORM_FACTS`), `$env.FORM_FACTOR`
  (`desktop laptop server vm wsl`), `owner-unlocked` and `profile-has secrets` (link only). Settings are options:
  `dot set <group/module>.<key> <value> [--machine]`.
- A file the app later edits is drift: kept until `dot module adopt <file>` (into the module) or `dot module reset
  <file>` (module's copy back, edit preserved aside); `dot apply --force <group>/<module>` resets all.
- One-time change on installed machines: `migrations/<NNNN>-<slug>.nu` from `0000-sample.nu` (`up` only;
  `export const layer = "system"` runs as root). Fresh installs mark all as run, so a migration never replaces a
  declaration.
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

`dot log --trace` shows timing, `dot explain <path>` the writer. Agents run with `DOT_SYSTEM=skip` (or `--no-system`):
a system part is pending (exit 3). A root prompt on Luca's side takes a YubiKey touch, a finger or the password.
