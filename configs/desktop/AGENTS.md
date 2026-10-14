# desktop

Extends the root `AGENTS.md`. The Wayland desktop: the Hyprland compositor, the quickshell shell, the display
manager, terminals, browsers, document and media viewers and their theming.

## Modules

- `applications`: launcher entries for apps and TUIs that ship none (TUIs via `Terminal=true` and xdg-terminal-exec).
- `bookokrat`: a book reader; this module seeds its state file.
- `capgemini`: a work app launcher entry with an absolute Exec path.
- `chromium`: Chromium with the oomox/wal gtk theme seeded for new profiles.
- `color-grading`: wlr-gamma-control night/color grading over the hyprland protocol.
- `feather`: Monero wallet; wallets live in the syncthing folder, `.keys` stay password-encrypted.
- `firefox`: Firefox, profile created headless on first run.
- `ghostty`: the default terminal and xdg-terminal-exec target.
- `gparted`: partition editor.
- `gtk`: the gtk theme overlay (oomox), surviving palette regen.
- `hyprland`: the compositor config (Lua). See `hyprland/AGENTS.md`.
- `idle-guards`: units that hold sleep inhibitors while media plays, ssh is in use or an agent works.
- `jdownloader`: the swing download manager and its container-file entry.
- `kitty`: a secondary terminal.
- `konsole`: runs only as dolphin's terminal panel, themed to match.
- `libreoffice`: office suite following the gtk/oomox theme.
- `ly`: the TUI display manager (binary `ly-dm`).
- `mpv`: the video player.
- `nsxiv`: the image viewer.
- `obsidian`: notes, with the Local REST API and MCP served by obsidian while it runs.
- `oomox`: the gtk/icon theme generator fed from the wallpaper palette.
- `pipewire`: the audio server, lanes and eq chains, roles. See `pipewire/AGENTS.md`.
- `plasma`: the few KDE/dolphin settings kept (global view properties).
- `printing`: cups and avahi for printer discovery.
- `qbittorrent`: torrent client bound to the ProtonVPN tunnel (proton0).
- `quickshell`: the bar, launcher, lock, notifications and OSD shell. See `quickshell/AGENTS.md` and the `l-dotfiles-quickshell-dev` skill.
- `qutebrowser`: the keyboard browser, per-user copy with absolute paths.
- `shimoji`: wlshm desktop mascots (shimeji).
- `thunderbird`: the mail client.
- `uwsm`: the universal wayland session manager launching the hyprland session.
- `zathura`: the pdf viewer, its config including the wal palette.

## Conventions

- Hyprland config is Lua (`hl.*`); dispatch is Lua too (see root gotchas). See `hyprland/AGENTS.md`.
- GUI programs take the wallpaper palette through wallust/oomox templates (`core/wallust`, `core/themes`), not a
  hardcoded theme; a theme switch dirties the tree.
- Background GUI testing stays off the user's screen: use a headless output (see root gotchas), never a visible
  workspace unless the user is working on that task.
