# programming

- Toolchains install eagerly in `link` (`exec ... --creates` or a plan-time check), so the first build or LSP start
  works offline; never lazily on first launch.
- MCP servers: `mcp-servers` in the owning module, only when the tool is installed, pinned when third-party, local
  (stdio or loopback).
- Package-only modules (`toolchains`, `python`, `security`, `vcs`, `http`, `infra`, `devtools`): a package goes into
  the module that uses it, else the closest of these.
- Formatter configs live in `programming/formatting` and are passed by nvim's conform (from the repo) and Doom's
  apheleia (from copies in `~/.config/doom/formatting`) as the fallback when a project has none, never linked. The
  exception is latexindent and chktex: they and texlab find their configs by path, so those are copied into
  `~/.config`.
- Emacs is Doom: a pinned checkout in `~/.config/emacs`, the repo's `doom/` files copied to `~/.config/doom`, and
  `doom sync` as a step keyed on the pin, `init.el`, `packages.el` and the emacs package. `init.el` stays Doom's
  default apart from the enabled modules; own settings go in `config.el`. The theme verb writes a palette theme and
  the font into the wal cache and reloads a running emacs over emacsclient.
- Owner-only modules (`bugwarrior`, `jai`, `projects`) gate on the owner actually being unlocked
  (`owner-unlocked`: the secrets profile AND the YubiKey), not `profile-has secrets` alone. `projects` runs after
  `core/gh`.
- Telemetry off for every agent and editor.
