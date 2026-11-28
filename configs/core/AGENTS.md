# core

The user-layer baseline on every machine.

- A themed program ships a wallust template (`core/wallust`), never a hardcoded palette: `l-dotfiles-theming`.
- Toggles: `l-dotfiles-toggles`.
- Owner-only modules (`ntfy`, `syncthing`, `proton/pass`, `proton/sessions`) gate on `owner-unlocked`
  (`l-dotfiles-secrets-access`). `proton/vpn`'s `auto-vpn` gates on `profile-has secrets` alone, like base's owner
  rollouts (`configs/base/AGENTS.md`). `git`'s (and jj's) identity is the owner's only when `owner-unlocked`; any other
  login's is `core/git.user_name` and `user_email`, each falling back to the profile's own where the profile lacks the
  secrets capability; without both, none. `gnupg`'s default-key only when `owner-unlocked`. `nas` is system layer: it
  mounts only with the `homelab` fact and the `samba-homelab` secret.
- `nushell` and `zsh` hold the generic shell config only: an alias or def for a tool is `shell-aliases` in the module
  that declares the tool (gated on the tool when the module does not declare it).
- `yt-dlp` goes through a fail-closed wrapper into the VPN namespace wherever `base/protonvpn-netns` is configured and
  `core/yt-dlp.vpn_only` is on (`vpn-routed`, also read by `desktop/mpv`); elsewhere bare `/usr/bin/yt-dlp` runs direct.
- Shell functions and aliases (zshrc, config.nu, every `aliases.{zsh,nu}`) also run in agents' shells: root goes
  through `sudo-at-terminal`, which refuses an agent marker or a missing terminal (lint `lint-rc-escalation`).
- `herdr-open` only runs a `.herdr-create` that was allowed (`herdr-open allow <dir>`).
