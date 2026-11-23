---
name: l-dotfiles-platform-facts
description: "Choosing between a module option, a machine fact (platforms/*.nuon, platform-has) and a user capability (profiles/*.nuon, profile-has), the platform file keys, and adding a fact or capability. Load when a module must behave differently per machine or per user. Writing the module itself: l-dotfiles-add-module."
---

# platform-facts

## Which one

1. A setting: a typed option in `mod.nu` (prefer this). Valued in `platforms/<name>.options.nuon` (`dot set
   --machine`) or `~/.config/dotfiles/options.nuon` (`dot set`, only for `scope: user` options; default scope is
   machine). A server or custom machine keeps its values in root's `/etc/dotfiles/platform.options.nuon`, which
   `dot set` refuses.
2. A property of the machine (form factor, homelab, wireguard, own secure boot keys, `lsck0_snapshot`, the `offload`
   role `target` or `client`): a fact, read with `platform-has <fact>` or `$env.FORM_FACTOR`. The only gate a `system`
   verb may use.
3. A property of the person: `profile-has secrets`, user layer only. Personal rollouts gate on `owner-unlocked`
   (`l-dotfiles-secrets-access`).

Rules:

- Never a username or hostname check.
- `platform-has homelab` says the machine is on the lab, not who logs in: a `--profile custom` login on luca-pc has it
  too. Personal content (accounts, employer domains, bookmarks) goes behind the profile or into `configs/secrets/`.
- A homelab value (domain, address, subnet, mirror) is never a literal: `use platforms/homelab.nu [HOMELAB]` as the
  default of an option a platform may override, acted on only behind `platform-has homelab`.

## Platform file

`platform-load` (`scripts/lib/platform.nu`) takes the first of `/etc/dotfiles/platform.nuon` (server or custom),
`platforms/local.nuon`, `platforms/<name>.nuon` for the name in `/etc/dotfiles/platform` (missing file: error).
Keys (`PLATFORM_KEYS`): `hostname`, `label`, `form_factor` (desktop, laptop, server, vm, wsl; probed when unset),
`groups` (groups or `group/module`, never `secrets`; empty means all), `extra_packages` (also in
`mirror/packages.txt`), `facts`, `packages_keep`, `flatpak_keep`, `nix_keep`. Unknown keys or facts fail the load.
`platforms/server.nuon` is the server template.

## Add a fact

1. Add it to `PLATFORM_FACTS` in `scripts/lib/platform.nu`.
2. Set it in `facts` of the platforms that need it; unset is off.
3. Read it with `platform-has`. A module acting on a fact also undoes its work when the fact is unset.
4. `dot test lint`.

## Add a capability

`PROFILE_CAPABILITIES` in `scripts/lib/profile.nu` plus `profiles/<name>.nuon`. The live copy is
`~/.config/dotfiles/profile.nuon`, chosen at install or by `adduser-dotfiles`, never by login name.
