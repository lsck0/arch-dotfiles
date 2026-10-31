# core

The user-layer baseline on every machine.

- A themed program ships a wallust template (`core/wallust`), never a hardcoded palette: `l-dotfiles-theming`.
- Toggles: `l-dotfiles-toggles`.
- Owner-only modules (`nas`, `ntfy`, `syncthing`, `proton/pass`, `proton/sessions`) gate on `owner-unlocked` (the
  secrets profile AND the YubiKey actually unlocked), not on `profile-has secrets` alone, so a keyless owner-profile
  install stays generic.
  `git`'s identity and `gnupg`'s default-key are value-gated the same way and fall back to none.
- `nushell` and `zsh` hold the generic shell config only: an alias or def for a tool is `shell-aliases` in the module
  that declares the tool (gated on the tool when the module does not declare it).
- `yt-dlp` is a fail-closed wrapper into the VPN namespace, never bare `/usr/bin/yt-dlp`.
- Shell functions and aliases (zshrc, config.nu, every `aliases.{zsh,nu}`) also run in agents' shells: root goes
  through `sudo-at-terminal`, which refuses an agent marker or a missing terminal (lint `lint-rc-escalation`).
- `herdr-open` only runs a `.herdr-create` that was allowed (`herdr-open allow <dir>`).
