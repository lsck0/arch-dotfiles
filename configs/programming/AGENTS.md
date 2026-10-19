# programming

Extends the root `AGENTS.md`. Editors, language toolchains, debuggers, agent CLIs and their MCP servers.

## Modules

- Editors/IDEs: `nvim` (primary, plugins/LSP/parsers installed eagerly), `emacs` (offline fallback), `zed`, `vscode`
  (vim mode), `jetbrains` (toolbox), `godot` (editor plus a pinned godot-mcp addon), `unreal` (~60 GB, desktop only).
- Language toolchains: `cargo` (Rust), `ghcup` (Haskell), `opam` (OCaml), `elan` (Lean), `jai` (owner's beta from
  `~/sync/vendor`), `nix`, `flux` (flux-rs on its pinned nightly), `kani` (Rust model checker), `asm-lsp` (assembly).
- Debuggers/profilers: `gdb`, `cgdb`, `nnd`, `renderdoc`.
- Git/VCS: `lazygit`, `gh-dash`, `direnv` (devenv environments), `identity` (not a module: the `.identity/envrc`
  that `identity-init` gives a repo for its own git identity).
- Agent CLIs: `claude`, `copilot`, `gemini-cli`, `caveman`, `hermes`, `herdr` (see `core/herdr`).
- MCP servers for Claude: `docker`, `kubernetes`, `grafana` (homelab, read-only), `postgres`, `playwright`, plus the
  creative and pentesting MCPs in their own groups.
- Tooling/config: `formatting` (formatter configs, not linked; see below), `typos`, `bruno`, `rtk`, `task`
  (taskwarrior), `bugwarrior` (identity-only issue sync), `trmnl-claude` (per-panel status poster), `projects`
  (owner's repos), `flux`, `grafana`.
- Package-only modules (a `meta` and no verbs): `toolchains` (compilers, build systems, runtimes), `python`,
  `debugging` (debuggers, profilers, tracers), `security`, `verification`, `math`, `vcs`, `http`, `infra`, `devtools`.
  A package goes into the module that uses it, else into the closest of these.

## Conventions

- Toolchains install eagerly in the `link` verb so the first build/LSP start works offline (nvim plugins, emacs
  packages, elan's channel, flux's sysroot), never lazily on first launch: `exec` steps with `--creates` or a
  plan-time check, so a rerun costs nothing.
- An MCP server is wired with `json-merge` on `~/.claude.json`, present only when its tool is installed, pinned where
  third-party (release/content/checkout), and local (stdio or loopback). No public port.
- Formatter configs (clang-format, stylua, prettier, rustfmt, ruff) are not linked: nvim `conform` and emacs
  `apheleia` pass them. One source, `programming/formatting`.
- Telemetry off for every agent/editor that phones home (gemini-cli, bruno, zed, vscode, copilot).
- Identity-gated modules (`bugwarrior`, `jai`, `projects`, `task`) read `profile-has identity`, never a username.
- Module order can matter: `projects` runs after `core/gh` (`meta.deps`).
