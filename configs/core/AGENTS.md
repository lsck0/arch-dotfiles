# core

The user-layer baseline on every machine.

- A themed program ships a wallust template (`core/wallust`), never a hardcoded palette: `l-dotfiles-theming`.
- Toggles: `l-dotfiles-toggles`.
- Owner-only modules (`nas`, `ntfy`, `syncthing`, `proton/pass`) gate on `owner-unlocked` (the secrets profile AND
  the YubiKey actually unlocked), not on `profile-has secrets` alone, so a keyless owner-profile install stays generic.
  `git`'s identity and `gnupg`'s default-key are value-gated the same way and fall back to none.
- `yt-dlp` is a fail-closed wrapper into the VPN namespace, never bare `/usr/bin/yt-dlp`.
- `herdr-open` only runs a `.herdr-create` that was allowed (`herdr-open allow <dir>`).
