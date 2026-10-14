# socials

Extends the root `AGENTS.md`. Chat, voice and music clients.

## Modules

- `desktop`: the "desktop" tms project bookmark (a session scaffold run by `.tms-create`), not a UI app.
- `discord`: the Discord client; first run downloads the app (~150 MB), done here so the first launch opens clean;
  betterdiscord with content-pinned plugins and a theme generated from spotify's palette.
- `element`: the Matrix client, native Wayland on arch's electron.
- `spotify`: Spotify with spicetify theming (needs the client installed).
- `teamspeak`: TeamSpeak 6 (a CEF app) forced off XWayland to render at native scale.
- `telegram`: the Telegram client (binary in `/usr/sbin`).
- `apps`: the other chat and mail clients (packages only).

## Conventions

- Every client here is confined by AppArmor in `enforce` (see `base/apparmor`): they open other people's content.
- Palette and scaling follow the desktop conventions (wallust/oomox, XWayland scaling); clients that render through
  CEF/Chromium are pushed onto native Wayland rather than scaled on XWayland.
