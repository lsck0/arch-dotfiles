# core

The user-layer baseline on every machine.

- A themed program ships a wallust template (`core/wallust`), never a hardcoded palette: `l-dotfiles-theming`.
- Toggles: `l-dotfiles-toggles`.
- Owner-only modules (`gnupg`, `nas`, `ntfy`, `syncthing`, `proton/pass`) check `profile-has secrets`.
- `yt-dlp` is a fail-closed wrapper into the VPN namespace, never bare `/usr/bin/yt-dlp`.
- `herdr-open` only runs a `.herdr-create` that was allowed (`herdr-open allow <dir>`).
