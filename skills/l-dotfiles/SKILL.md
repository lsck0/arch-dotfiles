---
name: l-dotfiles
description: Source of truth for system configuration.
---

# l-dotfiles

This repository contains my system setup and configuration files, which are symlinked across the system.

## Layout

- `config/<name>`: config/setup for tools/tasks.
- `keyboard/`: the firmware for my keyboard.
- `scripts/`: scripts that are meant to be called directly.
- `skills/`: llm personas, prompts and my styles.
- `themes/`: color themes that are propagated through the system.
- `wallpapers/`: wallpapers which are either set through a theme or by itself and then have a theme dynamically generated.
- `weblinks/`: browser independent bookmarks.
- `install.sh`: list of installed packages and bootstrapping script.

## Conventions

- do not commit or push, I handle this manually with sync.sh
- all system settings have to be reproducible through running install.sh on a fresh system
