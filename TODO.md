# TODO

Open items from the luca-notebook review on 2026-11-05: each needs the PC, root, a foreign network, or a decision.

## Root or Luca's YubiKey

- [ ] Enroll the TPM2 token. `rd.luks.options` asks for one and every boot logs "No valid TPM2 token data found".
  `dot status` names the `systemd-cryptenroll` command.
- [ ] geoclue.service on luca-pc fails every hour: "start operation timed out" after 90 s, nothing logged by geoclue
  itself. Its bus activation comes from a client not yet found (geoclue is pulled in by gnome-calendar and gnome-maps).
  With root: `systemctl edit geoclue` with `Environment=G_MESSAGES_DEBUG=all`, or `strace -f` the next start. The
  sources to suspect are compass (iio-sensor-proxy on a desktop with no sensor) and wifi.
- [ ] Home detection trusts the gateway MAC alone (`ip neigh`, `arping` fallback). Both MACs were in the public repo's
  history before they moved to `configs/secrets/keys/`, and a router MAC cannot be rotated. Add a second check before
  home: the DHCP server identifier or the known gateway IP with its MAC. Test it on the notebook.
- [ ] Do the recovery drill (RECOVERY.md "Test it"), then run `dot secrets audit drilled`.

## Needs the PC

- [ ] Discord no longer shows "Streaming" while live on Twitch. Check these on the PC:
    - Discord, Connections, Twitch: "Display on profile" is on.
    - Activity Privacy: "Share your detected activities" is on.
    - Then turn off Incognito's `blockProcessScanning` and DoNotTrack's process monitoring, one at a time. Both stop the
      client's process detection (OBS included), and Incognito was added on 2026-10-14. If one of them is the cause, pin
      that setting to false in `configs/socials/discord/mod.nu`, as `blockReadReceipts` is.
- [ ] OBS alert sounds: `configs/desktop/pipewire/app-loopback.lua` now leaves `obs-browser-page` streams alone. The "...
  For Me" browser sources play there and were muted with every other loopback while HEAR was on. Check on the PC that a
  test alert plays both locally and on the stream. The other two, "Twitch Alerts" and "Sound Alerts", go through OBS
  tracks 1, 3 and 4 (`reroute_audio`).
