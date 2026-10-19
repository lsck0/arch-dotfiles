---
name: l-dotfiles
description: "Layout and conventions of Luca's arch-dotfiles repo (~/projects/arch-dotfiles), the source of truth for his system configuration: configs, platforms, install stages, dot sync, no agent commits. Load when working in that repo or changing any system setting."
---

# l-dotfiles

This repository contains my system setup and configuration files, applied by `dot` as managed, hash-recorded copies;
links only where an app reads the repo live.

`AGENTS.md` at the repo root is the working index: standing facts, verified commands, and the table of the topic skills `l-dotfiles-<topic>`. They are global, since they also cover the machine's system configuration: load the one a task needs. This skill is the always-on orientation; `AGENTS.md` and the topic skills carry the detail.

## Layout

- `configs/<group>/<name>`: config/setup for tools/tasks, including `configs/base/keyboard` (keyboard firmware).
- `themes/`: color themes propagated through the system, next to `wallpapers/`.
- `mirror/`: pkgbuilds and the local package mirror.
- `platforms/`: `<host>.nuon` machine facts and groups, `<host>.options.nuon` option values (luca-pc, luca-notebook,
  luca-wsl, test-vm, `templates/`).
- `profiles/`: per-user profile templates.
- `scripts/`: scripts that are meant to be called directly.
- `scripts/toggles/`: on/off switches for system features (wifi, vpn, dnd, ...), plus a menu and a status script.
- `secrets/`: git-crypt secrets submodule, committed by dot sync.
- `showcase/`: screenshots of the setup.
- `skills/`: llm personas, prompts and my styles.
- `wallpapers/`: wallpapers which are either set through a theme or by itself and then have a theme dynamically generated.
- `weblinks/`: browser independent bookmarks.
- `bootstrap.sh` (then `dot internal bootstrap`), `dot apply --packages`, `dot apply`, `dot internal stage`: install stages 1 to 3 (base system from the ISO, packages, user and system config) and the per-boot chain that runs them unattended.
- `dot sync`: the one command: pull, migrate, install, apply, back up live app state, signed `Generation: <n>` commit, push (`--no-push` stops before the backup).

## Conventions

- do not commit or push, I handle this manually with dot sync
- commits here are `Generation: <n>` via dot sync, not conventional commits (overrides l-style-tooling's Git section)
- all system settings have to be reproducible through the install stages on a fresh system
- agents run dot with `DOT_SYSTEM=skip` (or `--no-system`); exit 3 means a system part is pending
- never run `dot sync`: it pulls, commits and pushes
- an edit lands with `dot apply <group>/<module>`
