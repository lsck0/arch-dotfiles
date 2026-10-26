---
name: l-dotfiles-streaming
description: The OBS setup in configs/creating/obs (the Streaming, VirtualCam and Bare collections, profiles, websocket on 4455, obs-mcp, the bar's obs widget, the PNGTuber capture, the VirtualCam profile) and inspecting live apps (Spotify over CDP, Discord through its BetterDiscord command file). Load when changing or debugging the stream setup or poking a running Spotify or Discord.
---

# streaming

## OBS state

Three collections, each with its profile (OBS doesn't pair them; pick both):

- `Streaming` (profile Streaming): `configs/secrets/keys/obs-Streaming.json` (alert tokens), as is except the mic, which
  takes the detected `mic` option (the backup restores the secret's own device).
- `VirtualCam` (profile VirtualCam): `scenes/VirtualCam.json`. `Desktop` is the screen, `Webcam` the `Camera` (v4l2,
  option `webcam`, MJPG 1080p30) full frame; `Cam top left|top right|bottom left|bottom right` nest both, the cam a
  quarter wide in that corner. No audio.
- `Bare` (profile Recording): `scenes/Bare.json`, `Desktop` with Desktop Audio, Game Audio, Mic/Aux.

- Every `scenes/*.json` is a collection; a new one is a new file. `scene-render --machine` scales positions from its
  `resolution` to the canvas and fills `AuxAudioDevice1` and every `v4l2_input`; `scene-back` reverses it, minus the
  portal `RestoreToken`. Per machine: `scenes/<hostname>/<name>.json` (`host-seed`), preferred by apply, written by the
  backup.
- Profiles in `profiles/`, `basic.ini` with `@KEY@` placeholders. VirtualCam capped at 720p (`VIRTUALCAM_HEIGHT`; 4k
  YUYV is ~500 MB/s). Streaming outputs the full canvas (recording stays 4k) and scales only the stream to `STREAM_RES`
  (at most 1080 high, lanczos `RescaleFilter=4`): 1080p60, 6000 kbps CBR, keyint 2 (`streamEncoder.json`). Recording:
  `record_encoder` option (AV1 on vaapi, else h264 via vaapi, nvenc or x264), CQP 18, hybrid mp4, 60 s replay buffer.
- Tracks (`mixers` bitmask): 1 full mix, 2 mic, 3 apps without mic, 4 Twitch VOD (all but Spotify). Recordings take
  1 to 3 (`RecTracks=7`).
- OBS saves collection and profile over the live copies on exit: `dot apply --user creating/obs` refuses while OBS runs
  with changes. Live edits reach the repo through the `backup` verb (`dot sync`).
- Change a profile live with `SetProfileParameter` (AdvOut is read each stream start), so the exit save matches.
- PNGTuber Plus runs under `obs-gamecapture` (`configs/gaming/steam/steam-launch-options.nu`) for obs-vkcapture.

## Hearing the stream

HEAR in the mixer, `qs ipc -p ~/.config/quickshell call obs toggleListen` and `scripts/toggles/toggle-obs-listen.nu`
switch every track-1 input to monitor-and-output or none, always from OBS's live
`GetInputAudioMonitorType`/`GetInputAudioTracks`, never from remembered state: a collection can arrive with monitoring
on, which would play the app twice. It also sets `dot.obs-listen` on the default metadata, muting the per-app loopbacks
(`configs/desktop/pipewire`). The bar runs the toggle's `reconcile` on connect. App captures tap the app's own stream,
so system faders don't change what OBS hears.

## Inspect a running OBS

obs-websocket v5, `ws://127.0.0.1:4455`, password `server_password` in
`~/.config/obs-studio/plugin_config/obs-websocket/config.json`. Auth: `secret = base64(sha256(password + salt))`,
`auth = base64(sha256(secret + challenge))` from Hello (op 0), sent in Identify (op 1). `obs-mcp` does this;
`plugins/bar/widgets/obs-status.nu` is a websocat client to copy.

The bar's obs widget runs `obs-status.nu` (the `~/.config/quickshell` copy) while OBS runs. It finds captures by input
kind and `Mic/Aux`, `Desktop Audio`, `Game Audio` by name: renaming breaks it. Edits need `dot apply
desktop/quickshell`, then an OBS restart or `configs/desktop/quickshell/restart.nu`.

## Spotify

`--remote-debugging-port=9233` (`DEVTOOLS_PORT` in `configs/socials/spotify/spotify-reload.nu`):

```bash
curl -s http://127.0.0.1:9233/json/list | jq -r '.[] | "\(.type) \(.url) \(.webSocketDebuggerUrl)"'
echo '{"id":1,"method":"Runtime.evaluate","params":{"expression":"document.title"}}' | websocat -n1 <webSocketDebuggerUrl>
```

## Discord

No CDP. `configs/socials/discord/plugins/QuickshellVoiceStatus.plugin.js` writes voice state to
`$XDG_RUNTIME_DIR/quickshell-discord-voice.json` and runs JSON lines `{"cmd": ...}` from
`$XDG_RUNTIME_DIR/quickshell-discord-cmd` (unlinked on read; write a temp file and `mv` it). Commands:
`toggleSelfMute`, `toggleSelfDeaf`, `disconnect`.
