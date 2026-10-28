---
name: l-dotfiles-add-package
description: Adding or removing a package in a module's meta (pacman, flatpak, nix), checking it is on the [lsck0] mirror, how removal works, and the supply-chain rules (pins, checksums, lockfiles, the known floating sources). Load when a module needs a new program, download, uvx/npx tool or git source.
---

# add-package

## Where

- The module that needs it, in its meta:
  ```nu
  export const meta = {packages: {pacman: [btop], native: [], flatpak: {"org.app.Id": "<commit>"}, nix: []}}
  ```
  `native`: hardware-only, skipped on WSL. flatpak pinned to a commit (installed `--user` and masked; bump with
  `flatpak remote-info --log flathub <app>`); nix by `NIXPKGS` in `scripts/lib/run.nu`.
- One machine only: `extra_packages` in `platforms/<name>.nuon` (this machine: `/etc/dotfiles/platform`); these also
  land in `mirror/packages.txt`.
- `dot internal packages [pacman|flatpak|nix] [--groups g,g --form-factor f]` prints what is declared;
  `dot internal gen` rewrites `mirror/packages.txt` (lint fails when stale).

## Steps

1. Add the name, then `dot internal gen`.
2. Check the mirror serves it (nothing is built on the machine): `pacman -Sp --print-format '%n %r' <pkg>` must say
   `<pkg> lsck0`. `target not found`: the mirror lacks it (`FAILURES.install` says `not on the mirror: <pkg>`). Own
   pkgbuilds in `mirror/pkgbuilds/`, missing AUR deps in `mirror/overrides.conf`.
3. `dot apply --packages`. Never `pacman -S` by hand.

## Removing

Delete the name. `dot apply --packages` removes what the ledger owns and nothing declares, then every explicit package
no module declares (minus the platform's `packages_keep` and `PACKAGES_DENY` in `scripts/lib/ledger.nu`), each after a
yes (`--yes` skips). `dot plan` lists them.

## Supply chain

Every source is pinned and checked:

- pacman: `SigLevel = Required`; `[lsck0]` signed by its own key. Its AUR packages build from AUR recipes, so the
  signature proves the builder, not the recipe: read the PKGBUILD and maintainer first.
- Downloads: `fetch-file <url> <sha256> <dest>`, never bare curl or `curl | sh`. Git: `fetch-git <url> <commit>
  <dir>`, a commit, not a branch or tag (`configs/programming/caveman`).
- `uvx`: `--exclude-newer <date>` plus `--from <pkg>==<version>` (`configs/creating/audacity`); a bare pin leaves
  dependencies floating.
- node: committed `package-lock.json` with `npm ci` (`configs/creating/obs/mcp`); `npx -y <pkg>@<version>` floats.
- The repo: `bootstrap.sh`, the iso stub and `system-apply.nu` refuse a HEAD not signed by
  `SIGNING_KEY_FINGERPRINT`; `merge.verifySignatures` makes the sync pull refuse unsigned commits.

Still floating, fix when touching the module:

- `npx` without lockfile: `configs/programming/kubernetes` (`kubernetes-mcp-server@0.0.67`),
  `configs/programming/godot/godot-mcp.nu` (`godot-mcp-server@0.6.0`), `configs/programming/caveman` (`skills@1.7.0`).
- `uvx` without `--exclude-newer`: `configs/latex/zotero` (`zotero-mcp-server==0.14.1`), `configs/pentesting/wireshark`
  (`wireshark-mcp==3.0.0`), `configs/programming/docker` (`mcp-server-docker==0.3.0`).
- Latest-version installs: mason (`configs/programming/nvim/lua/lib/mason_packages.lua`), the VSCodium vim extension,
  Firefox and Chromium store extensions (`policies.json`, `policy.json`), rustup toolchains, Claude Code plugins other
  than caveman.
- `mirror/pkgbuilds` resolving dependencies at build time with no lockfile or hashes: `bloodyad` (pip `--target`
  installs `badldap` and `kerbad` plus their transitive deps), `bruno-cli` and `kulala-fmt` (`npm install -g` of the
  registry tarball; `kulala-fmt` also runs tree-sitter install scripts).
