---
name: l-dotfiles-add-module
description: "Writing a module's mod.nu under configs/: meta, typed options, the fixed verbs and hooks, declarations, actions with undo, linked scripts, and running one module alone. Load when adding, porting or restructuring a module, or when a new program, service or setting needs one. A package for an existing module: l-dotfiles-add-package; per-machine behaviour: l-dotfiles-platform-facts."
---

# add-module

A module is one folder `configs/<group>/<module>/` with a `mod.nu`; `dot` discovers its verbs, options and packages,
nothing central changes. Read the group's `AGENTS.md` first. Sources in declarations are relative to the module dir:
`config/foo.conf`, `services/foo.service`, `scripts/foo.nu`. An owner-only module (employer setup, bookmarks, key
wiring) goes in `configs/secrets/<module>/` (id `secrets/<module>`): same contract, runs after every other group
wherever the submodule is pulled, gates inside itself (`owner-unlocked` in `link`, `$env.FORM_FACTOR` in `system`), and
its packages stay off `mirror/packages.txt` (a mirror package it needs goes in the platform's `extra_packages`).

## The contract

```nu
use module.nu *

export const meta = {
    deps: [core/gh]                                   # modules that apply first, any group (theme pass included)
    reads: [base/ssh]                                 # options read from cfg.deps only: no ordering
    packages: {pacman: [btop], native: [], flatpak: {}, nix: []}  # installed versions are in the input hash
    serial: false                                     # true: runs alone (rustup, a package manager)
    inputs: [configs/secrets/state/repositories]      # more input-hash files (never its own package's binary)
    volatile: false                                   # true: always evaluated (reads machine state)
    backup: {secrets: true}                           # its backup verb writes into secrets: runs only unlocked
    secrets: ["alloy/{host}"]                         # what its system verb reads of keys/ (root gets only these)
    phase: early                                      # install stage role: early (base/pacman) or install
    native_only: [system]                             # verbs not evaluated on WSL
    barrier: {run: boot-commit, watch: [/etc/x]}      # export run once after a layer's apply changed a watched
                                                      # path
}

export const options = {
    accent: {
        type: string                                  # nu type name: list<string>, int, bool, string? ...
        default: c4
        doc: "Palette slot for titles and the selection"
        label: "Accent colour"                        # settings UI; also group, choices, min/max/step
        choices: [c1 c2 c3 c4 c5 c6]
        apply: live                                   # live (needs an apply verb or toggle) | relink | relogin | reboot
        scope: user                                   # default machine (platform only); user: the profile may set it
    }
}

# user layer: returns declarations, writes nothing itself
export def link [cfg: record] {
    [
        (files-into (xdg config btop) config/btop.conf)
        (unit-file services/oom-notify.service --enable --now)
        (if $cfg.accent == "c1" { file-text (xdg config btop extra.conf) "x\n" })
    ]
}

# root, from the root-owned copy; never a user fact
export def system [cfg: record] {
    file-copy config/smartd.conf /etc/smartd.conf --then (unit-restart smartd.service --if-running)
}

export def theme [cfg: record, wallpaper: string] {
    let p = palette-load
    if $p == null { return [] }
    file-text (xdg config btop themes pywal.theme) $"theme[title]=\"($p | get $cfg.accent)\"\n" --generated
}

export def apply [cfg: record] { theme $cfg "" }          # a live option's hook, after dot set
```

## Rules

- Verbs (`VERBS` in `scripts/lib/modules.nu`): `link`, `system`, `theme`, `apply`, `backup`, `restore`, `update`
  (what floats outside pacman, run by `dot sync`). Hooks (`HOOKS`): `detect [cfg]: nothing -> record` fills options
  platform and profile left null (a failure only warns), probed only for a module of the platform's groups and, in a
  run naming modules, only for those and what their `meta.deps` and `meta.reads` name; `packages [cfg]: nothing ->
  record` adds option-dependent packages. Any other export (besides `meta` and `options`) is a `step` target or
  imported by another module; everything else is a plain `def` or `const` (lint checks).
- A module is evaluated again only when its input hash changes: its dir, the files it imports, of `scripts/lib` only
  what its evaluation loads (`lib-stamp` in `scripts/lib/pipeline.nu`), its packages' versions, `meta.inputs`, the
  platform facts and profile capabilities.
- A verb returns declarations nested to any depth; null and `[]` add nothing. An optional entry is
  `(if <cond> { decl })`, never `else { [] }` or a trailing `| compact`. A value other code consumes (`++`, `append`,
  a spread) still needs its `else`.
- Evaluation never touches the network: verbs and hooks read local state only; downloads go in a `step` or `exec`
  with `--network`.
- Engine helpers come from `module.nu` only (lint `ENGINE_INTERNAL`). Reading another module's options needs it in
  `meta.reads` or `meta.deps`.
- `system` gates only on platform facts and `$env.FORM_FACTOR`; `owner-unlocked` and `profile-has` are `link` only.
  Which to use: `l-dotfiles-platform-facts`. Settings are options: `dot set <group/module>.<key> <value> [--machine]`.
- A disabled or deleted module declares nothing on the next full run: its files, links and units go, merged json keys
  return to their old values (unless edited since), and each recorded action runs its `--undo`. No unlink needed first.
- Recorded actions (`--creates`, `--key`, `--done` or `--undo`) run once; a plain `exec` runs on every evaluation and
  what it did stays. Never a stamp file of its own.
- A helper a unit, toggle or keybind runs is a script in the module's `scripts/`, installed with `link-commands` or
  `files-into`. A root helper follows AGENTS.md's argv rule (`core/toggles/scripts/toggle-root.nu`; pass-through
  `base/protonvpn-netns/scripts/run.sh`).
- A linked script finds the repo with `const REPO = path self | path expand | path dirname --num-levels <depth>`, one
  level per directory between the file and the repo: 5 in `configs/<group>/<module>/scripts/`, 6 in a nested module's
  (`core/proton/sessions/scripts/`); lint `LINKED_RELATIVE` checks the pattern, not the depth. Any other file uses
  `path self` with a relative path (`path self ../../../..` in `scripts/`, `../../..` at the module's top), one more
  `..` in a nested module.
- The user layer already loads `configs/base/xdg/config/app-dirs.conf`; never copy its variables into a module.
- A one-time change on installed machines is a migration, never a substitute for a declaration:
  `migrations/<NNNN>-<slug>.nu` from `0000-sample.nu` (`up` only; `export const layer = "system"` runs as root).

Read [reference.md](reference.md) when writing declarations: the full catalogue (files, rules, units, actions,
reactions, pending, fetch), helpers, timeouts, what root runs, drift, and backup verbs.

## Run it alone

```bash
dot plan <group>/<module>          # actions; empty after the apply
DOT_SYSTEM=skip dot apply <group>/<module>
dot module unlink <group>/<module> # reverse it
dot plan --system <group>/<module> # the system verb, planned as the user
dot test lint                      # refs, layer rules, the module's *.test.nu
dot test check                     # formatters, linters, nu parse gate
```

`dot log --trace` shows timing, `dot explain <path>` the writer.
