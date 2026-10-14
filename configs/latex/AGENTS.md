# latex

Extends the root `AGENTS.md`. The LaTeX authoring stack.

## Modules

- `latex`: the texlive toolchain and build config.
- `sioyek`: the pdf reader for papers, with SyncTeX forward/inverse search; command on PATH, invoked bare by nvim/viewers.
- `zotero`: the reference manager, profile created headless on first run.

## Conventions

- SyncTeX edit flow between the reader and the editor is AppArmor-mediated (`base/apparmor abstractions/synctex-edit`,
  `profiles/sioyek`); both sioyek and zotero stay `enforce` (they open other people's documents).
- Authoring conventions (project layout, preamble, macros, theorems) are Luca's, in the `l-style-latex` skill, not here.
