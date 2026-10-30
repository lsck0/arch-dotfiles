# socials

- `desktop` is a tms/herdr project bookmark (`.tms-create`, `.herdr-create`), not an app.
- `discord`: the first apply downloads the client; BetterDiscord plugins are content-pinned. BetterDiscord's
  before-quit migration writes a resources/app shim into each new host version; it and the hook's core injection load
  the one data/betterdiscord.asar main.js, which runs once. The core injection matters only for a host BetterDiscord
  never migrated (the first install); the hook still relaunches a fresh host even when the shim already loaded it.
- BetterDiscord reads plugins.json only at startup and rewrites it from memory: a merge reaches a running client only
  after a restart. A plugin file renamed over is disabled, so plugins are copied in place.
- CEF/Chromium clients run native Wayland, not scaled XWayland.
- `spotify`: always starts with Chrome DevTools on 127.0.0.1:9233 for the streaming tooling. CDP has no auth, so
  any local process can drive the logged-in session; accepted on purpose; CEF binds it to loopback only.
- Clients with an AppArmor profile run enforce; teamspeak6-client, proton-meet-bin, chatuino-bin, discordo-git and
  spotify-player have none yet.
