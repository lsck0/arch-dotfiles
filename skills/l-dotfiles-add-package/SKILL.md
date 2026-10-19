---
name: l-dotfiles-add-package
description: Adding or removing a package in a module's meta (pacman, flatpak, nix), checking it is on the [lsck0] mirror, and how removal works. Load when a module needs a new program.
---

# add-package

## Where

- The module that needs it, in its `mod.nu` meta:
  ```nu
  export const meta = {packages: {pacman: [btop], native: [], flatpak: {"org.app.Id": "<commit>"}, nix: []}}
  ```
  `native` is the hardware-only half, skipped on WSL. A flatpak is pinned to a commit (installed `--user` at it and
  masked; bump with `flatpak remote-info --log flathub <app>`), nix by `NIXPKGS` in `scripts/dot.nu`.
- One machine only: `extra_packages` in `platforms/<host>.nuon`.
- `dot internal packages [pacman|flatpak|nix]` prints what this machine declares; `dot internal gen` rewrites
  `mirror/packages.txt`, the list the homelab mirror builds (`dot test lint` fails when it is stale).

## Steps

1. Add the name, then `dot internal gen`.
2. Check the mirror serves it; nothing is built on the machine:
   ```bash
   pacman -Sp --print-format '%n %r' <pkg>
   ```
   `<pkg> lsck0` is good; `error: target not found` means the mirror lacks it (`not on the mirror: <pkg>` in
   `FAILURES.install`). Own pkgbuilds live in `mirror/pkgbuilds/`, missing deps of AUR recipes in
   `mirror/overrides.conf`.
3. `dot apply --packages` installs it. Never `pacman -S` by hand: `dot plan` lists it as declared by no module.

## Removing

Delete the name. `dot apply --packages` removes what the ledger owns and nothing declares, then every explicitly
installed package no module declares (minus `packages_keep` in the platform file and the boot/unlock deny list), each
after a yes at the tty; `dot plan` lists them.
