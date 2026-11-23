---
name: l-dotfiles
description: "Every change to this machine goes through ~/projects/arch-dotfiles and its dot command. Load before installing a package or tool (pacman, pip, npm -g, cargo, flatpak, curl | sh), adding a service, timer or udev/polkit rule, editing /etc, ~/.config or ~/.local/bin, putting something on PATH, when any project needs a machine change, or working in that repo. Topics: the l-dotfiles-* skills."
---

# l-dotfiles

Nothing on this machine is changed by hand. The repo's `AGENTS.md` is the index: layout, commands, conventions and the
table of `l-dotfiles-<topic>` skills. From another project, follow `MACHINE.md`: message the `arch-dotfiles-*` session
with the exact need.

## Making a change

1. `dot explain <path|package>` names the owning module.
2. Edit that module (`configs/<group>/<module>/`, or an option in `platforms/<name>.options.nuon`), or add one:
   `l-dotfiles-add-module`, `l-dotfiles-add-package`.
3. `DOT_SYSTEM=skip dot apply <group>/<module>` converges its user layer. The `system` verb needs root:
   `dot plan --system <group>/<module>` shows what root would do; Luca runs `dot apply --system` (his next `dot sync`
   enters root for it too). Exit 3 means the system part is pending, not failed.
4. `dot test lint`; fix and rerun until clean, then report.

## Gotchas

- Never edit a file while a `dot sync` runs: it evaluates the checkout live, then commits it. Wait with
  `pgrep -f 'nu --no-config-file \S*(scripts/dot[.]nu|bin/dot) sync'`; a loose `pgrep -f 'dot.nu sync'` matches the
  waiting shell itself and never ends.
- Renaming or deleting a file that `~/.local/bin` or a unit links into the repo leaves the command dangling until its
  module's user layer is applied (`scripts/` is the module `scripts`). `find ~/.local/bin -xtype l` lists them.
- A comment-only edit of a file the system layer deploys still changes its hash: the next sync enters root and runs
  the file's `--then` (a restart). No cosmetic edits to deployed files.
