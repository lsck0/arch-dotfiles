---
name: l-dotfiles
description: "Luca's arch-dotfiles repo (~/projects/arch-dotfiles), the only way this machine is configured: its layout, the dot command, and the rule that every machine-level change goes through it. Load whenever an agent is about to install or remove a package or tool (pacman, pip, npm -g, cargo install, flatpak, curl installers), change a system or user setting, add or enable a service, unit, timer or udev/polkit rule, edit anything under /etc, ~/.config or ~/.local/bin, put something on PATH, or work inside the dotfiles repo; also when another project needs something on the machine."
---

# l-dotfiles

This machine is rebuilt from `~/projects/arch-dotfiles` by `dot`, and a fresh install must end up identical. Nothing
is changed by hand: a package, setting, unit or PATH entry is a file in this repo, applied by `dot`. The repo's
`AGENTS.md` is the working index, with the table of topic skills `l-dotfiles-<topic>`.

## Need from another project

An agent working elsewhere does not install anything. It messages the dotfiles session (list agents, the one named
`arch-dotfiles-*`) with the exact need ("adb and the emulator on PATH") and waits for confirmation. Project-local
dependencies (venvs, `node_modules`, devenv) stay in that project. Homelab changes: `l-homelab`.

## Making a change

1. `dot explain <path|package>` names the owning module.
2. Edit that module (`configs/<group>/<module>/`, or an option in `platforms/<name>.options.nuon`), or add one:
   `l-dotfiles-add-module`, `l-dotfiles-add-package`.
3. `DOT_SYSTEM=skip dot apply <group>/<module>`. The system layer needs root: it is recorded as pending (exit 3) and
   Luca runs `dot apply --system`.
4. `dot test lint` before reporting.

## Layout

- `configs/<group>/<module>/`: one tool or task; groups enabled per platform.
- `platforms/<name>.nuon` (luca-pc, luca-notebook, wsl, server, vm) and `<name>.options.nuon`. The machine's choice is
  `/etc/dotfiles/platform`; server or custom answers are `/etc/dotfiles/platform{,.options}.nuon`.
- `profiles/`: user profile templates (`secrets` marks the owner).
- `scripts/` (in `~/.local/bin`), `scripts/lib/` the engine, `scripts/toggles/` the switches.
- `themes/`, `wallpapers/` (public; bought ones in `~/sync/wallpapers`).
- `mirror/`: own pkgbuilds, the `[lsck0]` build list, `iso/`.
- `configs/secrets/`: private submodule; `keys/` git-crypt, `state/` plaintext app state, `<module>/` the owner's
  modules; anything else makes sync refuse (`l-dotfiles-secrets-access`).
- `skills/`: linked into the skills dir of each installed agent (claude, copilot, gemini, hermes). `showcase/`:
  screenshots.
- Install: `bootstrap.sh`, `dot internal bootstrap`, then `dot internal stage` runs `dot apply --packages` and
  `dot apply` across boots (`l-dotfiles-install`).

## Rules

- Never commit, push or run `dot sync`; Luca does. Commits are `Generation: <n>`, not conventional commits
  (overrides `l-style-tooling`).
- Run `dot` with `DOT_SYSTEM=skip` (or `--no-system`); exit 3 means a system part is pending.
- Every setting reproducible on a fresh system. dot never writes into `~/sync`, except the
  `**/.identity` line `core/syncthing` keeps in `~/sync/.stignore`; reading is fine.
