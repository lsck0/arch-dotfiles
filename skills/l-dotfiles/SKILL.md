---
name: l-dotfiles
description: Source of truth for system configuration.
---

# l-dotfiles

This repository contains my system setup and configuration files, which are symlinked across the system.

## Layout

- `configs/<name>`: config/setup for tools/tasks, including `configs/keyboard` (keyboard firmware) and `configs/themes` (color themes propagated through the system).
- `mirror/`: pkgbuilds and the local package mirror.
- `patches/`: patch scripts for upstream packages.
- `platforms/`: per-machine scripts (luca-pc, luca-notebook, test-vm).
- `scripts/`: scripts that are meant to be called directly.
- `showcase/`: screenshots of the setup.
- `skills/`: llm personas, prompts and my styles.
- `wallpapers/`: wallpapers which are either set through a theme or by itself and then have a theme dynamically generated.
- `toggles/`: on/off switches for system features (wifi, vpn, dnd, ...), plus a menu and a status script.
- `weblinks/`: browser independent bookmarks.
- `install.sh`: list of installed packages and bootstrapping script.
- `sync.sh`: stages everything, makes a signed `Generation: <n>` commit and pushes.

## Conventions

- do not commit or push, I handle this manually with sync.sh
- commits here are `Generation: <n>` via sync.sh, not conventional commits (overrides l-style-tooling's Git section)
- all system settings have to be reproducible through running install.sh on a fresh system
