---
name: l-dotfiles-add-package
description: Adding or removing a package in a module's meta (pacman, flatpak, nix), checking it is on the [lsck0] mirror, how removal works, and the supply-chain rules (pins, checksums, lockfiles, the known floating sources). Load when a module needs a new program, download, uvx/npx tool or git source.
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

## Supply chain

Everything a module pulls in runs as the user or as root, so each source is pinned and checked. The rules, then
what still floats:

- pacman: signed (`SigLevel = Required`); the `[lsck0]` mirror is signed by its own key. Its AUR packages are built
  from AUR recipes by the homelab builder, so the signature proves who built a package, not that the recipe is
  benign. Before adding an AUR package, read its PKGBUILD and check who maintains it.
- flatpak: a commit (above). nix: `NIXPKGS` in `scripts/dot.nu`.
- A download: `fetch-file <url> <sha256> <dest>` (`scripts/lib/module.nu`), never a bare curl, and never `curl | sh`.
  A git source: `fetch-git <url> <commit> <dir>`, a commit and not a branch or tag (see `configs/programming/caveman`).
- python tools through `uvx`: `--exclude-newer <date>` plus `--from <pkg>==<version>` (see
  `configs/creating/audacity`). A bare `<pkg>==<version>` pins only the top package, and its dependencies resolve
  fresh on every start.
- node tools: a committed `package-lock.json` installed with `npm ci` (see `configs/creating/obs/mcp`).
  `npx -y <pkg>@<version>` pins only the top package; its dependency tree floats.
- The repo itself: `bootstrap.sh`, the iso stub and `system-apply.nu` refuse a HEAD that is not signed by
  `SIGNING_KEY_FINGERPRINT`, and `merge.verifySignatures` makes `dot sync`'s pull refuse unsigned commits.

Known floating sources, fix them when touching the module:

- `npx` with no lockfile: `configs/programming/kubernetes` (`kubernetes-mcp-server@0.0.67`),
  `configs/programming/godot/godot-mcp.nu` (`godot-mcp-server@0.6.0`), `configs/programming/caveman`
  (`skills@1.7.0`).
- `uvx` with no `--exclude-newer`: `configs/latex/zotero` (`zotero-mcp-server==0.14.1`), `configs/pentesting/wireshark`
  (`wireshark-mcp==3.0.0`), `configs/programming/docker` (`mcp-server-docker==0.3.0`).
- Tools installed at their latest version: mason (`mason-tool-installer` in
  `configs/programming/nvim/lua/plugins/lsp.lua`), the VSCodium vim extension (`configs/programming/vscode`), and the
  browser extensions Firefox and Chromium force from their stores (`policies.json`, `policy.json`), which update
  themselves. Rustup toolchains and Claude Code plugins other than caveman also float.
