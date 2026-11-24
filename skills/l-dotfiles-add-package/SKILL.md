---
name: l-dotfiles-add-package
description: Adding or removing a package in a module's meta (pacman, native, flatpak, nix), checking the [lsck0] mirror serves it, how removal asks, and the supply-chain pins (fetch-file, fetch-git, mcp-uvx, npm ci, pins.test.nu). Load when a module needs a new program, download, PyPI or npm tool, or git source. A whole new module is l-dotfiles-add-module.
---

# add-package

## Steps

1. Declare it in the module that needs it:
   ```nu
   export const meta = {packages: {pacman: [btop], native: [], flatpak: {"org.app.Id": "<commit>"}, nix: []}}
   ```
   `native`: hardware-only, skipped on WSL. flatpak is pinned to a commit (installed `--user` and masked; bump with
   `flatpak remote-info --log flathub <app>`); nix by `NIXPKGS` in `scripts/lib/run.nu`. One machine only:
   `extra_packages` in `platforms/<name>.nuon`.
2. `dot internal gen` rewrites `mirror/packages.txt` (lint fails when stale). `dot internal packages [kind]
   [--groups g,g --form-factor f]` prints what is declared.
3. Check the mirror serves it; nothing is built on the machine. `pacman -Sp --print-format '%n %r' <pkg>` must print
   `<pkg> lsck0`. `target not found`: a name new to `mirror/packages.txt` arrives with the mirror's next nightly build
   (`FAILURES.install` says `not on the mirror: <pkg>` until then). Own pkgbuilds go in `mirror/pkgbuilds/`, missing
   AUR deps in `mirror/overrides.conf`.
4. `dot apply --packages`, never `pacman -S` by hand. pacman is root's, so Luca runs it (or his `dot sync`); an agent's
   `DOT_SYSTEM=skip dot apply --packages` does flatpak, nix and the user layer and leaves pacman pending (exit 3).

Without the `homelab` fact, `base/pacman` leaves `[lsck0]` out of `pacman.conf` while the mirror does not answer, so its
packages wait.

## Removing

Delete the name. `dot apply --packages` then removes, each after a yes on `/dev/tty` (a run waiting there:
`l-dotfiles-live-debug`):

1. what the ledger installed and nothing declares any more;
2. packages installed by hand that no module declares, minus the platform's `packages_keep`, `flatpak_keep` or
   `nix_keep` and `PACKAGES_DENY` in `scripts/lib/ledger.nu` (flatpak: apps only, `flatpak list --user --app`).

`--yes` skips both questions for pacman; hand-installed flatpak and nix packages are always asked.

Nothing is removed while a module fails to declare its packages; `dot plan` lists what would go. Flatpaks are unmasked
first and unused runtimes go after. A removed nix package stays in the store until `base/cleanup`'s weekly
`nix-gc.timer` collects generations older than 30 days.

## Supply chain

Every source is pinned and checked:

- pacman: `SigLevel = Required`, `[lsck0]` signed by its own key. Its AUR packages build from AUR recipes, so the
  signature proves the builder, not the recipe: read the PKGBUILD and its maintainer before adding one.
- Downloads: `fetch-file <url> <sha256> <dest>`, never bare curl or `curl | sh`. Git: `fetch-git <url> <commit> <dir>`,
  a commit, never a branch or tag.
- PyPI: `mcp-uvx <name> <pkg>==<version> <date> [argv] <module>` builds a venv at apply time with `--exclude-newer`
  the date (the pin's upload date or later), since a bare pin leaves dependencies floating. No `uvx` at run time.
- node: a committed `package-lock.json` installed by `mcp-npm` (`npm ci`; `configs/creating/obs/config/mcp`);
  `npx -y <pkg>@<version>` floats.
- The repo itself: `bootstrap.sh`, the iso stub and `system-apply.nu` refuse a HEAD not signed by
  `SIGNING_KEY_FINGERPRINT`; `dot sync` merges nothing unless origin's head carries that signature.

`scripts/lib/pins.test.nu` (in `dot test lint`) fails on a floating source missing from its `EXCEPTIONS` and warns on a
pin older than 90 days, a pin with no ISO date in a comment on or above its line (`# v1.0.3, 2026-09-11`), and an
exception matching nothing.

Still floating; fix when touching the module. The lint-tracked ones are `EXCEPTIONS` in `pins.test.nu`; these it
cannot see:

- mason (`configs/programming/nvim/config/lua/lib/mason_packages.lua`), rustup-managed tools, Claude Code plugins
  other than caveman.
- `configs/llm/vllm`: `vllm==<release>+<rocm tag>` from `wheels.vllm.ai`, an index without upload times, so no
  `--exclude-newer` and no hash.
- `configs/programming/kani`: `cargo kani setup` downloads its bundle unchecked.
- Toolchains that track their channel by choice: elan's Lean `nightly` (`configs/programming/elan`), the sdkmanager
  package ids (`configs/programming/android`), act's `catthehacker/ubuntu:act-*` images
  (`configs/programming/act/config/actrc`).
- Game content tracking upstream by design: d2launcher's `mxl-install`, dalamud's `plugin-restore.nu` (host, names,
  versions and the manifest's sha1s are checked).
- AUR `-git` packages in `mirror/packages.txt` build from upstream HEAD. Privileged or always sourced: `it87-dkms-git`,
  `python-validity-git`, `endlessh-git`, `oh-my-zsh-git`, `fzf-tab-git`. The fix is an own pkgbuild pinned with
  `#commit=`.
