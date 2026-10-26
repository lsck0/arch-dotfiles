# programming

- Toolchains install eagerly in `link` (`exec ... --creates` or a plan-time check), so the first build or LSP start
  works offline; never lazily on first launch.
- MCP servers: `mcp-servers` in the owning module, only when the tool is installed, pinned when third-party, local
  (stdio or loopback).
- Package-only modules (`toolchains`, `python`, `debugging`, `security`, `verification`, `math`, `vcs`, `http`, `infra`,
  `devtools`): a package goes into the module that uses it, else the closest of these.
- Formatter configs live in `programming/formatting` and are passed by nvim's conform and emacs' apheleia, not linked.
- Owner-only modules (`bugwarrior`, `jai`, `projects`, `task`) check `profile-has secrets`. `projects` runs after
  `core/gh`.
- Telemetry off for every agent and editor.
