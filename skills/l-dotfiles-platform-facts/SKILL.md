---
name: l-dotfiles-platform-facts
description: Machine facts in platforms/<name>.nuon versus user capabilities in profiles/<name>.nuon versus per-module options, which to use, and adding a fact. Load when a module must behave differently per machine or per user.
---

# platform-facts

## Which one

- A per-module setting (a render node, remote unlock, an accent colour): a typed option in the module's `mod.nu`,
  valued per machine in `platforms/<name>.options.nuon` (`dot set --machine`) or per user in
  `~/.config/dotfiles/options.nuon` (`dot set`); an option with `scope: machine` only through `--machine`. A server or
  custom machine's values are root's `/etc/dotfiles/platform.options.nuon`, which `dot set` refuses to write. Prefer
  this.
- A property of the machine every module may ask (form factor, homelab network, wireguard config, own secure boot keys,
  `lsck0_snapshot` the pinned mirror date): a platform fact, `platform-has <fact>` / `$env.FORM_FACTOR`. The only gate a
  `system` verb may use.
- A property of the person logged in: the one profile capability, `profile-has secrets` (the owner). User layer
  only.
- Never a username or hostname check.

## Platform file

`platform-load` (`scripts/lib/platform.nu`) picks, first match: `/etc/dotfiles/platform.nuon` (a generic machine's
answers from `bootstrap.sh`), `platforms/local.nuon`, `platforms/<name>.nuon` for the name in `/etc/dotfiles/platform`.
Keys: `hostname`, `form_factor` (desktop, laptop, server, vm, wsl; probed when unset), `groups` (all but `secrets` when
unset; an entry is a group, or `group/module` for that one module; `secrets` is never listed, it runs wherever the
submodule is pulled, and listing it fails the load), `extra_packages` (also in `mirror/packages.txt` after `dot internal
gen`), `facts`, `packages_keep` (hand-installed packages to keep). Unknown keys or facts fail the load.
`platforms/server.nuon` is the server template: bootstrap takes its groups and form factor, merges
`server.options.nuon`, and writes both to `/etc/dotfiles` with the asked hostname.

## Add a fact

1. Add it to `PLATFORM_FACTS` in `scripts/lib/platform.nu`.
2. Set it in the `facts` of the `platforms/<name>.nuon` that need it; unset is off.
3. Read it: `platform-has my_fact`. A module that acts on a fact also undoes its work when the fact is unset.
4. `dot test lint`.

Hyprland reads the form factor from `~/.config/hypr/platform.lua` (`form_factor`, `laptop`), which
`desktop/hyprland`'s link verb generates from `$env.FORM_FACTOR` and its options on every run.

## Add a capability

Add it to `PROFILE_CAPABILITIES` in `scripts/lib/profile.nu` and to `profiles/<name>.nuon`. The live copy is
`~/.config/dotfiles/profile.nuon`, copied once from the profile picked in `bootstrap.sh` or `adduser-dotfiles`; the
login name never selects one.
