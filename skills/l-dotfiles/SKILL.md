---
name: l-dotfiles
description: "Luca's arch-dotfiles repo (~/projects/arch-dotfiles), the only way this machine is configured: its layout, the dot command, and the rule that every machine-level change goes through it. Load whenever an agent is about to install or remove a package or tool (pacman, pip, npm -g, cargo install, flatpak, curl installers), change a system or user setting, add or enable a service, unit, timer or udev/polkit rule, edit anything under /etc, ~/.config or ~/.local/bin, put something on PATH, or work inside the dotfiles repo; also when another project needs something on the machine."
---

# l-dotfiles

This machine is rebuilt from `~/projects/arch-dotfiles` by one command, `dot`, and a fresh install must end up
identical. So nothing on it is changed by hand: a package, setting, unit or PATH entry is a file in this repo, applied
by `dot`. Managed files are hash-recorded copies; links only where an app must read the repo live.

`AGENTS.md` at the repo root is the working index (verified commands, conventions, gotchas) with the table of the
topic skills `l-dotfiles-<topic>`. This skill is the orientation; load the topic skill a task needs.

## When the need comes from another project

An agent working elsewhere (a game, a paper, a service) that needs something on the machine does not install it. It
messages the dotfiles session (list agents, the one named `arch-dotfiles-*`) with the exact need, e.g. "adb and the
emulator on PATH", and waits for the confirmation. Project-local dependencies (venvs, `node_modules`, devenv, files
inside the project) stay that project's own. Homelab changes go through the homelab session instead: `l-homelab`.

## Making a change here

1. Find the owner: `dot explain <path|package>` names the module that writes a file or declares a package.
2. Edit that module (`configs/<group>/<module>/mod.nu`, its files, an option in `platforms/<name>.options.nuon`), or
   add one: `l-dotfiles-add-module`, `l-dotfiles-add-package`.
3. `DOT_SYSTEM=skip dot apply <group>/<module>` for the user layer. The system layer needs root: an agent never gets
   it, so the run records it as pending (exit 3) and Luca runs `dot apply --system`.
4. `dot test lint` before reporting.

## Layout

- `configs/<group>/<module>/`: one tool or task each, groups enabled per platform.
- `platforms/<name>.nuon`: machine facts and groups (pc, notebook, wsl, server, vm); `<name>.options.nuon` its
  option values. A named machine's choice is `/etc/dotfiles/platform`; a server or custom machine's answers are
  `/etc/dotfiles/platform{,.options}.nuon`.
- `profiles/`: per-user profile templates (`secrets` marks the owner).
- `scripts/`: commands linked into `~/.local/bin`; `scripts/lib/` the engine; `scripts/toggles/` the on/off and
  n-state switches with their menu and status.
- `themes/` and `wallpapers/`: color themes and the public wallpapers; the bought ones live in `~/sync/wallpapers`.
- `mirror/`: own pkgbuilds and the `[lsck0]` package mirror's build list; `mirror/iso/` the install ISO.
- `configs/secrets/`: the private submodule. `keys/` holds the git-crypt secrets, `state/` the plaintext backed-up
  app state (dalamud, ffxiv, firefox, repositories), `<module>/mod.nu` the owner's own modules (yubikey, capgemini,
  weblinks). Anything else there makes sync refuse. Skill `l-dotfiles-secrets-access`.
- `skills/`: these skills, Luca's style guides and personas, linked into every agent's skills dir.
- `showcase/`: screenshots.
- Install: `bootstrap.sh` then `dot internal bootstrap`, `dot apply --packages`, `dot apply`, with `dot internal stage`
  running them unattended across boots. Skill `l-dotfiles-install`.

## Rules for agents

- Never commit, push or run `dot sync`: it pulls, commits the signed `Generation: <n>` and pushes. Luca runs it.
  Commits are `Generation: <n>`, not conventional commits (overrides `l-style-tooling`'s Git section).
- Run `dot` with `DOT_SYSTEM=skip` (or `--no-system`); exit 3 means a system part is pending.
- Every setting must be reproducible through the install stages on a fresh system.
- dot never writes into `~/sync`; reading it is fine.
