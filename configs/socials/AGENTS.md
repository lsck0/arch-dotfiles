# socials

- `desktop` is a tms/herdr project bookmark (`.tms-create`, `.herdr-create`), not an app.
- `discord`: the first apply downloads the client; BetterDiscord plugins are content-pinned. BetterDiscord's
  before-quit migration writes a resources/app shim into each new host version; it and the hook's core injection load
  the one data/betterdiscord.asar main.js, which runs once. The core injection matters only for a host BetterDiscord
  never migrated (the first install); the hook still relaunches a fresh host even when the shim already loaded it.
- BetterDiscord reads plugins.json only at startup and rewrites it from memory: a merge reaches a running client only
  after a restart. A plugin file renamed over is disabled, so plugins are copied in place.
- CEF/Chromium clients run native Wayland, not scaled XWayland.
- `spotify` (9233, the streaming tooling) and `fluxer` (9234, the bar's voice widget) always start with Chrome
  DevTools on 127.0.0.1. CDP has no auth: whoever connects drives the logged-in session. Each module's system verb
  hands its port (the `DEVTOOLS_PORT` its launcher uses) to `devtools-guard` from base/nftables, whose always-loaded
  `fw-devtools` resets loopback connections to those ports from any uid but the desktop owners'
  (`/var/lib/dotfiles/owners`, every login's without one): service users and a second login are kept off. A new CDP
  port is one more `devtools-guard` line. `fluxer-voice` reads the port only while a process of its own uid listens
  there and follows only a debugger url on it; another uid's listener is logged once and left alone.
- Clients with an AppArmor profile run enforce; teamspeak6-client, proton-meet-bin, chatuino-bin, discordo-git,
  fluxer-bin and spotify-player have none yet.
