# TODO

What is left needs Luca: root, the YubiKey, the PC's live apps, or another machine. Everything else from the
2026-11-05 to 2026-11-08 reviews is done in the working tree and lands with the next `dot sync`.

## After the next `dot sync`

- [ ] `dot apply --system` on each machine. It brings, among others: `tries=0` on the LUKS prompt (a mistyped
  passphrase asks again instead of the locked emergency shell), `mq-deadline` on NVMe and nix-daemon at
  `IOSchedulingClass=idle`, geoclue's `GIO_USE_VFS=local` drop-in (its hourly 90 s start timeout), the Capgemini
  policies from `configs/secrets/capgemini`, and home detection's three-value check.
- [ ] `dot apply --packages`: `hermes-agent-desktop` is missing, so `programming/hermes` (and its MCP servers) stays
  pending until then. `github-desktop-bin`, `hermes-agent-desktop` and `tokui` are in `mirror/packages.txt` but not
  built on the lsck0 mirror yet.
- [ ] `dot apply desktop/idle-guards`: the agent guard now walks past shell parents (Gemini runs hooks through
  `bash -c`). Then check one live Gemini and one Copilot session keep the machine awake and release it at the end.
- [ ] Restart Steam once: the running client still carries `MANGOHUD=1`, so fossilize_replay keeps crashing until then.

## Root or Luca's YubiKey

- [ ] Enroll the TPM2 token. `rd.luks.options` asks for one and every boot logs "No valid TPM2 token data found".
  `dot status` names the `systemd-cryptenroll` command.
- [ ] Home detection now needs gateway MAC, gateway address and DHCP server identifier together
  (`configs/secrets/keys/home-gateways`, `<mac> <gateway> <dhcp server id>`; a MAC-only line gives trusted, not home).
  Line 1 was migrated on luca-pc. Line 2 is a MAC luca-pc does not see: complete it with its gateway and server id
  if it is still a home router (the notebook's view), else delete it. Then check `/run/home-network` on the notebook.
  The address and server id are not secret (192.168.178.1 is the FritzBox default): this stops a MAC clone, not a
  router built from the public repo; pinning the router's https certificate would be the stronger factor.
- [ ] Do the recovery drill (RECOVERY.md "Test it"), then run `dot secrets audit drilled`.

## Needs the PC

- [ ] Discord no longer shows "Streaming" while live on Twitch. Check these on the PC:
    - Discord, Connections, Twitch: "Display on profile" is on.
    - Activity Privacy: "Share your detected activities" is on.
    - Then turn off Incognito's `blockProcessScanning` and DoNotTrack's process monitoring, one at a time. Both stop the
      client's process detection (OBS included), and Incognito was added on 2026-10-14. If one of them is the cause, pin
      that setting to false in `configs/socials/discord/mod.nu`, as `blockReadReceipts` is.
    - Discord also no longer goes to Idle/Away on its own when the PC is left alone. Likely cause: Incognito's
      `disableIdle` is `true` in `~/.config/BetterDiscord/plugins/Incognito.config.json`. If turning it off fixes it,
      pin `disableIdle` to false in `configs/socials/discord/mod.nu` too.
- [ ] OBS alert sounds: `configs/desktop/pipewire/app-loopback.lua` now leaves `obs-browser-page` streams alone. The
  "... For Me" browser sources play there and were muted with every other loopback while HEAR was on. Check on the PC
  that a test alert plays both locally and on the stream. The other two, "Twitch Alerts" and "Sound Alerts", go
  through OBS tracks 1, 3 and 4 (`reroute_audio`).

## VM test

- [ ] `dot test run --scenario lab-down` and `--scenario config-fail` (new on 2026-11-08): a generic install with the
  whole lab down (the `[lsck0]` fallback) and a failed config stage (its login banner). Hours each, 12 GB of RAM; run
  when the PC is free.
