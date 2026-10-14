# core

Extends the root `AGENTS.md`. The user-layer baseline on every machine: shell, prompt, terminal multiplexer,
version control, backups, theming and the toggle framework. Each module is a `mod.nu`; its packages are in its meta.

## Modules

- `borg`: scheduled `$HOME` backup into the syncthing folder the NAS receives (homelab users only). See root backup model.
- `btop`: resource monitor, themed by wallust.
- `cli`: the command-line tools with no config of their own (packages only).
- `fastfetch`: system summary.
- `gh`: GitHub CLI and credential storage.
- `git`: git config; a user without an identity keeps the generic config.
- `gnupg`: gpg config and the shipped public key, imported for the matching identity.
- `herdr`: the herdr agent runner command on PATH, invoked bare by tmux/nvim/viewers.
- `locale`: language, LC_TIME, keyboard layout and Wi-Fi country (options, detected from what bootstrap set).
- `nas`: the NAS mount (system verb) and a homelab user's `~/nas` shortcut.
- `ntfy`: notification forwarder to the homelab ntfy (homelab users with a token only).
- `nushell`: nushell config sourcing vendor init scripts.
- `proton/pass`: the `pass` password store, linked into `~/sync`; Proton auth is manual (README.md), no credentials in the repo.
- `starship`: shell prompt.
- `syncthing`: the `~/sync` syncing daemon and folders (primary home for live shared data; see root).
- `themes`: the `themes/*.json` palette definitions (data, copied by `wallust`).
- `timezone-auto`: network-based timezone updates.
- `tmux`: tmux config and autoreload.
- `toggles`: the on/off switch framework (`scripts/toggles`), its root half and polkit wiring. See the `l-dotfiles-toggles` skill.
- `trash`: daily trash cleanup for home and tmpfs trash.
- `veracrypt`: veracrypt volume tooling (the mount prompt needs a terminal, link only hints).
- `wallust`: the theming engine, its templates and `palette.nu`, the colour authority. See the `l-dotfiles-theming` skill.
- `yazi`: file manager, theme rendered by wallust.
- `yt-dlp`: a fail-closed wrapper routing through the VPN namespace or refusing, never bare `/usr/bin`.
- `zsh`: the login shell config.

## Conventions

- Theming flows through `wallust` and `themes/*.json`; a themed program ships a template here, not a hardcoded palette.
  A theme switch dirties the tree (generated files through repo symlinks; see root gotchas).
- A toggle is `scripts/toggles/toggle-*.nu` with a root half and quickshell/menu wiring. See the `l-dotfiles-toggles` skill.
- Identity-gated modules (`gnupg`, `nas`, `ntfy`, `borg`, `syncthing`) read `profile-has`, never a username.
