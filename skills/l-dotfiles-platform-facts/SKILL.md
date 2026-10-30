---
name: l-dotfiles-platform-facts
description: Machine facts in platforms/<name>.nuon versus user capabilities in profiles/<name>.nuon versus per-module options, which to use, and adding a fact. Load when a module must behave differently per machine or per user.
---

# platform-facts

## Which one

- Per-module setting: a typed option in `mod.nu`, valued in `platforms/<name>.options.nuon` (`dot set --machine`) or
  `~/.config/dotfiles/options.nuon` (`dot set`). Options default to machine scope; `scope: user` for per-user ones.
  A server or custom machine's values are root's `/etc/dotfiles/platform.options.nuon` (`dot set` refuses it). Prefer
  this.
- Property of the machine (form factor, homelab, wireguard, own secure boot keys, `lsck0_snapshot`): a platform fact,
  `platform-has <fact>` / `$env.FORM_FACTOR`. The only gate a `system` verb may use.
- Property of the person: `profile-has secrets` (the owner). User layer only.
- Never a username or hostname check.

## Platform file

`platform-load` (`scripts/lib/platform.nu`) takes the first of `/etc/dotfiles/platform.nuon` (server or custom),
`platforms/local.nuon`, `platforms/<name>.nuon` for the name in `/etc/dotfiles/platform` (a missing file is an error).
Keys: `hostname`, `label`, `form_factor` (desktop, laptop, server, vm, wsl; probed when unset), `groups` (entries are
groups or `group/module`; never `secrets`), `extra_packages` (also in `mirror/packages.txt`), `facts`,
`packages_keep`, `flatpak_keep`, `nix_keep` (spared when undeclared packages are removed). Unknown keys or facts fail
the load. `platforms/server.nuon` is the server template.

## Add a fact

1. Add it to `PLATFORM_FACTS` in `scripts/lib/platform.nu`.
2. Set it in the `facts` of the platforms that need it; unset is off.
3. Read it with `platform-has`; a module acting on a fact also undoes its work when it's unset.
4. `dot test lint`.

## Add a capability

`PROFILE_CAPABILITIES` in `scripts/lib/profile.nu` plus `profiles/<name>.nuon`. The live copy is
`~/.config/dotfiles/profile.nuon`, chosen at install or by `adduser-dotfiles`, never by login name.
