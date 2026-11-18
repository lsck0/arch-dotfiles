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
3. `DOT_SYSTEM=skip dot apply <group>/<module>` converges that module's user layer. Its `system` verb needs root:
   `dot plan --system <group>/<module>` shows what root would do, then Luca runs `dot apply --system` (his next
   `dot sync` enters root for it too). A full `DOT_SYSTEM=skip dot apply` records the system layer as pending (exit 3).
4. `dot test lint` before reporting.

## In the checkout

- Never edit a file while a `dot sync` runs: it evaluates the checkout live and then commits it. Wait for Luca's with
  `pgrep -f 'nu --no-config-file \S*(scripts/dot[.]nu|bin/dot) sync'`; a loose `pgrep -f 'dot.nu sync'` matches the
  waiting shell itself and never ends.
- A renamed or deleted file that `~/.local/bin` or a unit links into the repo leaves the command dangling until its
  module's user layer is applied (step 3; `scripts/` is the module `scripts`). `find ~/.local/bin -xtype l` lists
  what dangles.
- A comment-only edit of a file the system layer deploys still changes its hash: the next sync enters root and runs
  the file's `--then` (a restart). No cosmetic edits to deployed files.
