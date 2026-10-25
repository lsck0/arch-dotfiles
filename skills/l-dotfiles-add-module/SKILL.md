---
name: l-dotfiles-add-module
description: Creating a configs/<group>/<module>/mod.nu (meta with deps and packages, typed options, the fixed verbs and steps), how dot picks it up, and running it alone. Load when adding, porting or restructuring a module.
---

# add-module

A module is one folder, `configs/<group>/<module>/`, with a `mod.nu`. Nothing central changes: `dot` discovers the
folder, its verbs (the commands it exports), its options and its packages.

A module only the owner wants (an employer's setup, their bookmarks, their own keys' wiring) goes in the private
submodule instead: `configs/secrets/<module>/mod.nu`, id `secrets/<module>`, group `secrets`. Same contract; it runs
after every other group, on every machine that pulled the submodule (gate it inside: `profile-has` in `link`, a platform
fact such as `$env.FORM_FACTOR` in `system`), its code is plaintext (only `configs/secrets/keys/` is git-crypt), and its
packages stay out of `mirror/packages.txt`, so one it needs from the mirror goes in the platform's `extra_packages`.
`dot test lint` checks its layer rules like any other.

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

# hook: values for options left null by platform and profile (hardware, live state), run before resolving
export def detect [cfg: record]: nothing -> record {
    {accent: (if (gpu-list | is-empty) { c2 } else { null })}
}

# hook: packages that depend on an option, merged into meta.packages
export def packages [cfg: record]: nothing -> record {
    {pacman: (if $cfg.accent == c4 { [btop-extra] } else { [] })}
}
```

- Verbs, a fixed set (`VERBS` in `scripts/lib/modules.nu`): `link`, `system`, `theme`, `apply` (an option's live
  apply), `backup`, `restore`, `update` (what floats outside pacman, run by `dot sync` after the apply). Any other
  exported command is a `step` target of the same mod.nu or a name another module imports (`use ../x/mod.nu
  [name]`); everything else is a plain `def` (`dot test lint` checks it). A helper a unit, toggle or keybind runs is a
  script file in the module dir, installed by `link-commands` or `files-into`. Each verb takes the resolved options
  record (`enable` is always there) and
  returns a declaration or a list of them (`decls-flatten` flattens nested lists). A module turned off (`enable`
  false, its group gone from the platform) is planned with nothing declared on the next full `link` or `system` run,
  so its recorded files, links and units are removed and disabled; what a `step` or `exec` did is not recorded and
  stays, so declare anything that must go with the module.
- Hooks (`HOOKS` in `scripts/lib/modules.nu`), not verbs: `detect` returns a record of option values, used where
  platform and profile leave an option null (a failure only warns, the options stay unset); `packages` returns a
  `{pacman, native, flatpak, nix}` part appended to `meta.packages` for packages that follow an option.
- Declarations (`scripts/lib/module.nu`): `file-copy <src> <dest>` (a real copy, hash recorded; `--then` runs when it
  changed), `files-into <dir> <src...>`, `file-text <dest> <text> [--generated] [--in-place]`, `file-render <src>
  <dest> {KEY: value}` (`@KEY@`), `file-link <src> <dest>` (only where the app must read the repo live),
  `link-commands <file...>`, `json-merge <file> [(json-set [k k] v) (json-delete [k])]`, `ini-merge <file> {section:
  {key: v}} [--missing-only]` (only those keys), `unit-file <src> [--enable --now]`, `unit-enable|unit-disable|
  unit-mask <name> [--now]`, `unit-restart <name> [--reload]` (a `--then` that skips a unit not installed yet),
  `dropin <unit> <src> [--name]`, `desktop-override <id> {|text| ...}`, `exec <name> [argv] [--creates path]`, `step
  <command> [args]` (one of the module's own exported commands, run at apply time on live state), `fetch-file <url>
  <sha256> <dest> [--extract <member>]` and `fetch-git <url> <commit> <dir>` (pinned downloads and checkouts),
  `group-admins <group>` (a system group every wheel member is in), `user-hook <name> <script> --watch [paths]`
  (a path unit that runs the script on a change), `palette-load` (the current palette or null, for `theme`).
- Option keys: `type`, `default`, `doc` (required); `label`, `group`, `choices`, `min`/`max`/`step`, `apply`
  (default relink), `scope` (default user), `toggle` (a live option set through `scripts/toggles/toggle-<name>.nu`:
  `on`/`off` for a bool, else `set <value>`; its `get` is the live value the settings window shows).
- Facts: `platform-has homelab|wireguard|secure_boot_own_keys|lsck0_snapshot` (machine; `PLATFORM_FACTS` in
  `scripts/lib/platform.nu`), `$env.FORM_FACTOR` (`desktop laptop server vm wsl`, not the platform file's name),
  `profile-has secrets` (user, link only). A per-module setting is an option, set with `dot set <group/module>.<key>
  <value> [--machine]`.
- A file the app later edits is drift: `dot plan` shows it, apply keeps it until `dot module adopt <file>` (copies it
  back into the module) or `dot apply --force <group>/<module>` (preserves it aside).
- A one-time move (an old path, a renamed state dir) is a `migrations/<NNNN>-<slug>.nu` copied from `0000-sample.nu`;
  `export const layer = "system"` runs it as root.
- A program that rewrites its own config over the copy (OBS, apps that save on exit) needs a `backup` verb that
  carries the live file back into the repo or `configs/secrets/`; `dot sync` runs it. State that differs per machine
  (resolution, devices, layout, logins) goes to `host-file <dir> <file>` (`<dir>/<host>/<file>`), so machines never
  overwrite each other's; the restore reads `host-seed <dir> <file>` (this machine's copy, else the shared seed
  `<dir>/<file>`), a credential only `host-file` (no seed: a new machine logs in itself). Theme output is no state:
  strip it in the backup instead.

## Run it alone

```bash
dot plan <group>/<module>          # actions, touching nothing; again after the apply, it should be empty
dot apply <group>/<module>         # its user layer; a second run is a no-op
dot module unlink <group>/<module> # reverse it; apply again restores it
dot plan --system <group>/<module> # the system verb, planned as the user
dot test lint                      # module refs, layer rules per verb, the module's *.test.nu
dot test check                     # formatters and linters, the nu parse gate
```

`dot log --trace` shows where the time went, `dot explain <path>` which module and run wrote a file.

Agents and tests run with `DOT_SYSTEM=skip` (or `--no-system` on `dot set`, `dot apply`, `dot sync`): nothing reaches
sudo or pkexec, a machine option's system part is only recorded as pending (exit 3). A root prompt on Luca's screen asks
for his YubiKey: polkit's PAM stack (and sudo's) tries pam_u2f first, a touch without a PIN, then an enrolled finger,
then the password.
