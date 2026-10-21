---
name: l-dotfiles-streaming
description: The OBS setup in configs/creating/obs (the Streaming, VirtualCam and Bare collections, profiles, websocket on 4455, obs-mcp, the bar's obs widget, the PNGTuber capture, the VirtualCam profile) and inspecting live apps (Spotify over CDP, Discord through its BetterDiscord command file). Load when changing or debugging the stream setup or poking a running Spotify or Discord.
---

# streaming

## OBS state

- Collections, three, each meant for the profile of its use (obs has no pairing, pick both in the menus):
  - `Streaming` (profile Streaming): the stream and record setup, from `configs/secrets/keys/obs-Streaming.json`
    (alert tokens), installed as is but for the mic, which takes the machine's detected `mic` option (the backup puts
    the secret's own device back).
  - `VirtualCam` (profile VirtualCam): `configs/creating/obs/scenes/VirtualCam.json`. Scene `Desktop` holds the screen
    capture, scene `Webcam` the `Camera` (v4l2, option `webcam`, detected by-id, MJPG 1080p30) full frame, so its crop
    and filters live in one place; `Cam top left|top right|bottom left|bottom right` nest `Desktop` and `Webcam`, the
    latter a quarter of the canvas wide in that corner. Switching scene moves the cam, `Desktop` is the one without it.
    No audio sources: the virtual camera carries none.
  - `Bare` (profile Recording): `scenes/Bare.json`, scene `Desktop`, the screen capture with Desktop Audio, Game
    Audio and Mic/Aux. It was `Fullscreen` until `migrations/0001-obs-bare-collection.nu` renamed it.
- Every `scenes/*.json` in the module is a collection; `scene-render --machine` fits it to this machine: the items'
  absolute pos and bounds scale from its `resolution` to the canvas (the `*_rel` copies obs prefers then go), the
  mic and webcam options fill `AuxAudioDevice1` and every `v4l2_input`. `scene-back` carries them back without the
  portal `RestoreToken`. A new collection is a new file there and nothing else.
- Profiles `Streaming`, `Recording`, `VirtualCam` live in `configs/creating/obs/profiles/`; `basic.ini` keeps
  `@KEY@` placeholders. VirtualCam is capped at 720p (`VIRTUALCAM_HEIGHT`): the raw YUYV feed at 4k is ~500 MB/s.
  Streaming keeps the full canvas as output (its parallel recording stays 4k) and scales only the stream encoder to
  `STREAM_RES` (canvas aspect, at most 1080 high; `AdvOut RescaleFilter=4` lanczos, `0` disables it): Twitch ingests
  1080p60 at 6000 kbps CBR, keyint 2 (`streamEncoder.json`). Recording: full canvas, AV1 CQP 18, hybrid mp4,
  replay buffer 60 s.
- Audio tracks (a source's `mixers` bitmask): 1 the full mix (stream), 2 the mic alone, 3 the apps without mic, 4 the
  Twitch VOD track (all but Spotify). Recordings take tracks 1 to 3 (`RecTracks=7`).
- OBS writes its loaded collection and profile over the live copies on exit, so `dot apply --user creating/obs`
  refuses while OBS runs and anything changed; close OBS first. Live edits made in OBS reach the repo through the
  module's `backup` verb, which `dot sync` runs; `scene-back` keeps a repo edit OBS has not loaded yet.
- A live profile change without a restart: `SetProfileParameter` over the websocket (the advanced output reads
  `AdvOut` at each stream start), so the copy obs saves on exit matches the repo.
- PNGTuber Plus runs under `obs-gamecapture` (steam launch options, `configs/gaming/steam/steam-launch-options.nu`)
  so the obs-vkcapture source sees it.

## Hearing the stream

The mixer's HEAR switch (System / OBS output), `qs ipc call obs toggleListen` and
`scripts/toggles/toggle-obs-listen.nu` set every input on track 1 to monitor-and-output (restoring each one's
previous type when off) and set `dot.obs-listen` on the default metadata, which mutes the per-app loopbacks
(`configs/desktop/pipewire`) while obs runs. OBS keeps monitor types in the collection on exit, so the bar runs the
toggle's `reconcile` when it connects. App captures tap the app's own stream, which plays at full level: the system
faders never change what OBS hears.

## Inspect a running OBS

obs-websocket v5 on `ws://127.0.0.1:4455`, password `server_password` in
`~/.config/obs-studio/plugin_config/obs-websocket/config.json`. Auth: `secret = base64(sha256(password + salt))`,
`auth = base64(sha256(secret + challenge))` from the Hello (op 0), sent in Identify (op 1). `obs-mcp` (Claude MCP,
`obs-mcp.nu` reads the password at start) does this for you; `plugins/bar/widgets/obs-status.nu` is a working
websocat client to copy from.

The bar's obs widget runs `obs-status.nu` as a long-lived helper: it finds per-app audio inputs by their input name,
so a renamed input breaks it, and an edit to it takes effect only after the shell restarts
(`configs/desktop/quickshell/restart.nu`).

## Spotify

Launched with `--remote-debugging-port=9233` (`DEVTOOLS_PORT` in `configs/socials/spotify/spotify-reload.nu`, used by
`spotify-launch.nu`):

```bash
curl -s http://127.0.0.1:9233/json/list | jq -r '.[] | "\(.type) \(.url) \(.webSocketDebuggerUrl)"'
echo '{"id":1,"method":"Runtime.evaluate","params":{"expression":"document.title"}}' | websocat -n1 <webSocketDebuggerUrl>
```

## Discord

No CDP port. The BetterDiscord plugin `configs/socials/discord/plugins/QuickshellVoiceStatus.plugin.js` publishes
voice state to `$XDG_RUNTIME_DIR/quickshell-discord-voice.json` and runs JSON lines `{"cmd": ...}` written to
`$XDG_RUNTIME_DIR/quickshell-discord-cmd` (unlinked on read; write a temp file and `mv` it in). The commands
quickshell sends are `toggleSelfMute`, `toggleSelfDeaf`, `disconnect` (`Commons/DiscordControl.qml`).
