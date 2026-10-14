---
name: l-dotfiles
description: "Layout and conventions of Luca's arch-dotfiles repo (~/projects/arch-dotfiles), the source of truth for his system configuration: configs, platforms, install stages, dot sync, no agent commits. Load when working in that repo or changing any system setting."
---

# l-dotfiles

This repository contains my system setup and configuration files, which are symlinked across the system.

`AGENTS.md` at the repo root is the working index: standing facts, verified commands, and a table of the topic skills `l-dotfiles-<topic>` (install, add-module, add-package, apparmor-profile, theming, toggles, quickshell-dev, vm-test, secrets-access, platform-facts). They are global, since they also cover the machine's system configuration: load the one a task needs. This skill is the always-on orientation; `AGENTS.md` and the topic skills carry the detail.

## Layout

- `configs/<group>/<name>`: config/setup for tools/tasks, including `configs/base/keyboard` (keyboard firmware) and `configs/core/themes` (color themes propagated through the system).
- `mirror/`: pkgbuilds and the local package mirror.
- `platforms/`: per-machine scripts (luca-pc, luca-notebook, luca-wsl, test-vm).
- `profiles/`: per-user profile templates.
- `scripts/`: scripts that are meant to be called directly.
- `scripts/toggles/`: on/off switches for system features (wifi, vpn, dnd, ...), plus a menu and a status script.
- `secrets/`: git-crypt secrets submodule, committed by dot sync.
- `showcase/`: screenshots of the setup.
- `skills/`: llm personas, prompts and my styles.
- `wallpapers/`: wallpapers which are either set through a theme or by itself and then have a theme dynamically generated.
- `weblinks/`: browser independent bookmarks.
- `bootstrap.sh` (then `dot bootstrap`), `dot install`, `dot apply`, `dot stage`: install stages 1 to 3 (base system from the ISO, packages, user and system config) and the per-boot chain that runs them unattended.
- `dot sync`: backs up live app state, makes a signed `Generation: <n>` commit and pushes.

## Conventions

- do not commit or push, I handle this manually with dot sync
- commits here are `Generation: <n>` via dot sync, not conventional commits (overrides l-style-tooling's Git section)
- all system settings have to be reproducible through the install stages on a fresh system
