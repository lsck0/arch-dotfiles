---
name: l-dotfiles
description: "Luca's arch-dotfiles repo (~/projects/arch-dotfiles), the only way this machine is configured: its layout, the dot command, and the rule that every machine-level change goes through it. Load whenever an agent is about to install or remove a package or tool (pacman, pip, npm -g, cargo install, flatpak, curl installers), change a system or user setting, add or enable a service, unit, timer or udev/polkit rule, edit anything under /etc, ~/.config or ~/.local/bin, put something on PATH, or work inside the dotfiles repo; also when another project needs something on the machine."
---

# l-dotfiles

This machine is rebuilt from `~/projects/arch-dotfiles` by `dot`; nothing is changed by hand. The repo's `AGENTS.md`
is the index: layout, commands, conventions and the table of topic skills `l-dotfiles-<topic>`. From another project,
follow `MACHINE.md`: message the `arch-dotfiles-*` session with the exact need.

## Making a change

1. `dot explain <path|package>` names the owning module.
2. Edit that module (`configs/<group>/<module>/`, or an option in `platforms/<name>.options.nuon`), or add one:
   `l-dotfiles-add-module`, `l-dotfiles-add-package`.
3. `DOT_SYSTEM=skip dot apply <group>/<module>`. The system layer needs root: it is recorded as pending (exit 3) and
   Luca runs `dot apply --system`.
4. `dot test lint` before reporting.
