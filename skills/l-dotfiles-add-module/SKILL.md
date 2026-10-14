---
name: l-dotfiles-add-module
description: Creating a configs/<group>/<module>/mod.nu (meta with deps and packages, typed options, the link/system/theme/apply/unlink verbs), how dot picks it up, and running it alone. Load when adding, porting or restructuring a module.
---

# add-module

A module is one folder, `configs/<group>/<module>/`, with a `mod.nu`. Nothing central changes: `dot` discovers the
folder, its verbs (the commands it exports), its options and its packages.

## The contract

```nu
use module.nu *

export const meta = {
    deps: [core/gh]                                   # modules that apply first, any group
    packages: {pacman: [btop], native: [], flatpak: {}, nix: []}
    serial: false                                     # true: runs alone (rustup, a package manager)
    inputs: [secrets/repositories /usr/bin/cargo-kani] # more input-hash files: relative is the repo's, ~ and / as is
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
        scope: user                                   # user: the profile may set it; machine: the platform only
    }
}

# user layer: declarations of what it wants, nothing written here
export def link [cfg: record] {
    [
        (files-into ($nu.home-dir | path join .config btop) btop.conf)
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
    file-text ($nu.home-dir | path join .config btop themes pywal.theme) $"theme[title]=\"($p | get $cfg.accent)\"\n" --generated
}

# a live option's hook: dot set calls it after the value changed
export def apply [cfg: record] {
    theme $cfg ""
}
```

- Verbs: `link`, `system`, `theme`, `apply`, `unlink` (only for what the declarations cannot reverse; returns `exec`
  steps), `backup`, `restore`, `check`. Each takes the resolved options record (`enable` is always there) and
  returns a declaration or a list of them.
- Declarations (`scripts/lib/module.nu`): `file-copy <src> <dest>` (a real copy, hash recorded; `--then` runs when it
  changed), `files-into <dir> <src...>`, `file-text <dest> <text> [--generated]`, `file-render <src> <dest>
  {KEY: value}` (`@KEY@`), `file-link <src> <dest>` (only where the app must read the repo live),
  `link-commands <file...>`, `json-merge <file> [(json-set [k k] v) (json-delete [k])]`, `unit-file <src>
  [--enable --now]`, `unit-enable <name> [--now]`, `dropin <unit> <src> [--name]`, `desktop-override <id> {|text|
  ...}`, `exec <name> [argv] [--creates path]`.
- Facts: `platform-has homelab` (machine), `profile-has secrets` (user, link only), `$env.FORM_FACTOR`. A per-module
  setting is an option, set with `dot set <group/module>.<key> <value> [--machine]`.
- A file the app later edits is drift: `dot plan` shows it, apply keeps it until `dot adopt <file>` (copies it back
  into the module) or `dot link --force` (preserves it aside).
- A one-time move (an old path, a renamed state dir) is a `migrations/<NNNN>-<slug>.nu` with `up` (and `down`).

## Run it alone

```bash
dot plan <group>/<module>          # actions, touching nothing
dot link <group>/<module>          # apply; a second run is a no-op
dot unlink <group>/<module>        # reverse it; link again restores it
dot plan --system <group>/<module> # the system verb, planned as the user
dot test lint && dot test check  # layer rules per verb, nu parse gate
```

`dot log --trace` shows where the time went, `dot explain <path>` which module and run wrote a file.

Agents and tests run with `DOT_SYSTEM=skip` (or `--no-system` on `dot set`, `dot unset`, `dot apply`): nothing reaches
sudo or pkexec, a machine option's system part is only recorded as pending (exit 3). A root prompt on Luca's screen
asks for his YubiKey: polkit's PAM stack (and sudo's) tries pam_u2f first, a touch without a PIN, then an enrolled
finger, then the password.
