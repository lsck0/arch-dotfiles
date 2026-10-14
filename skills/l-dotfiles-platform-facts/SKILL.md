---
name: l-dotfiles-platform-facts
description: Machine facts in platforms/<host>.nuon versus user capabilities in profiles/<user>.nuon versus per-module options, which to use, and adding a fact. Load when a module must behave differently per machine or per user.
---

# platform-facts

## Which one

- A per-module setting (a render node, remote unlock, an accent colour): a typed option in the module's `mod.nu`,
  valued per machine in `platforms/<host>.options.nuon` (`dot set --machine`) or per user in
  `~/.config/dotfiles/options.nuon` (`dot set`). Prefer this.
- A property of the machine every module may ask (form factor, homelab network, wireguard config, own secure boot
  keys): a platform fact, `platform-has <fact>` / `$env.FORM_FACTOR`. The only gate a `system` verb may use.
- A property of the person logged in: a profile capability, `profile-has secrets|identity|homelab|work`. User
  layer only.
- Never a username or hostname check.

## Platform file

`platform-load` (`scripts/lib/platform.nu`) picks, first match: `/etc/dotfiles/platform.nuon` or `.sh` (a generic
machine's answers from `bootstrap.sh`), `platforms/local.nuon`, `platforms/<hostname>.nuon`. Keys:
`hostname`, `form_factor` (desktop, laptop, vm, wsl; probed when unset), `groups` (all when unset),
`extra_packages` (also in `mirror/packages.txt` after `dot gen`), `facts`, `packages_keep` (hand-installed packages to
keep). Unknown keys or facts fail the load.

## Add a fact

1. Add it to `PLATFORM_FACTS` in `scripts/lib/platform.nu`.
2. Set it in the `facts` of the `platforms/<host>.nuon` that need it, with a why-comment; unset is off.
3. Read it: `platform-has my_fact`. A module that acts on a fact also undoes its work when the fact is unset.
4. `dot test lint`.

Hyprland reads the form factor at runtime from `~/.config/dotfiles/form-factor`, written by every user-layer run.

## Add a capability

Add it to `PROFILE_CAPABILITIES` in `scripts/lib/profile.nu` (and `profile_has`'s comment in `profile.sh` while bash
modules read it) and to `profiles/<user>.nuon`, then `dot gen`. The live copy is `~/.config/dotfiles/profile.sh`
(copied once by `bootstrap.sh` or `adduser-dotfiles`), or `profile.nuon` beside it, which wins.
