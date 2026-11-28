---
name: l-dotfiles-streaming
description: "The OBS setup in configs/creating/obs (Streaming, VirtualCam and Bare collections and profiles, audio tracks, websocket on 4455, obs-mcp, the bar's obs widget, HEAR monitoring) and poking a running Spotify (CDP on 9233) or Discord (BetterDiscord command file). Load when changing or debugging the stream setup or inspecting those live apps."
---

# streaming

## Rules

- OBS saves collection and profile over the live copies on exit: `dot apply --user creating/obs` refuses while OBS runs
  with changes. Live edits reach the repo through the module's `backup` verb (`dot sync`).
- Change a profile on a running OBS with `SetProfileParameter` (AdvOut is read each stream start), so the exit save
  matches.
- The bar's `obs-status.nu` finds captures by input kind and `Mic/Aux`, `Desktop Audio`, `Game Audio` by name:
  renaming an input breaks it.
- Private parts live in secrets (`l-dotfiles-secrets-access`): the Streaming collection in `keys/obs/Streaming.json`
  (widget urls carry tokens), the stream art (overlays, PNGTuber gifs, badges, `.kra` sources) in `state/obs/`,
  referenced by absolute path. The public module holds no art.

## Collections and profiles

Three collections, each with its profile; OBS does not pair them, so pick both:

| collection | profile | source | content |
|---|---|---|---|
| `Streaming` | Streaming | `configs/secrets/keys/obs/Streaming.json` | as is, except the mic takes the `mic` option |
| `VirtualCam` | VirtualCam | `config/scenes/VirtualCam.json` | `Desktop`, `Webcam` (v4l2, option `webcam`, MJPG 1080p30), `Cam top left`.. corners with the cam a quarter wide; no audio |
| `Bare` | Recording | `config/scenes/Bare.json` | `Desktop` with Desktop Audio, Game Audio, Mic/Aux |

- Every `config/scenes/*.json` is a collection; a new one is a new file. `scene-render --machine` scales positions
  from its `resolution` to the canvas and fills `AuxAudioDevice1` and every `v4l2_input`; `scene-back` reverses it,
  minus the portal `RestoreToken`. Per machine: `config/scenes/<hostname>/<name>.json` (`host-seed`), preferred by
  apply, written by the backup.
- Profiles in `config/profiles/<name>/`, `basic.ini` with `@KEY@` placeholders filled by `mod.nu`.
- VirtualCam is capped at 720p (option `virtualcam_height`; 4k YUYV is about 500 MB/s).
- Streaming outputs the full canvas and scales only the stream to `STREAM_RES` (at most `stream_height`, 1080, lanczos
  `RescaleFilter=4`); `streamEncoder.json`: 6000 kbps CBR, keyint 2.
- Recording: `record_encoder` option (AV1 on vaapi, else h264 via vaapi, nvenc or x264), CQP 18, hybrid mp4; a 60 s
  replay buffer in the Recording and VirtualCam profiles, off in Streaming (`RecRB`, `RecRBTime`).
- Tracks (`mixers` bitmask): 1 full mix, 2 mic, 3 apps without mic, 4 Twitch VOD (all but Spotify). Recordings take 1
  to 3 (`RecTracks=7`).
- PNGTuber Plus runs under `obs-gamecapture` (`configs/gaming/steam/scripts/steam-launch-options.nu`) for obs-vkcapture.

## Hearing the stream

HEAR in the mixer, `qs ipc -p ~/.config/quickshell call obs toggleListen` and `scripts/toggles/toggle-obs-listen.nu`
switch every track-1 input between monitor-and-output and none, always read from OBS's live
`GetInputAudioMonitorType`/`GetInputAudioTracks`, never remembered: a collection can arrive with monitoring on, which
plays the app twice. It also sets `dot.obs-listen` on the default metadata (muting the per-app loopbacks of
`configs/desktop/pipewire`) and shows every `<name> For Me` scene item while off, hides it while on, so an alert is
heard once. The bar runs the toggle's `reconcile` on connect. App captures tap the app's own stream: system faders do
not change what OBS hears.

## Inspect a running OBS

obs-websocket v5 on `ws://127.0.0.1:4455`, password `server_password` in
`~/.config/obs-studio/plugin_config/obs-websocket/config.json`. Auth: `secret = base64(sha256(password + salt))`,
`auth = base64(sha256(secret + challenge))` from Hello (op 0), sent in Identify (op 1). `obs-mcp` does this;
`configs/desktop/quickshell/config/plugins/bar/widgets/obs-status.nu` is a websocat client to copy. An edit to it needs
`dot apply desktop/quickshell`; the running helper keeps its old code until OBS or the shell restarts
(`l-dotfiles-quickshell-dev`). Both are live apps: ask Luca before restarting either.

## Spotify

CDP on `--remote-debugging-port=9233` (`DEVTOOLS_PORT` in `configs/socials/spotify/scripts/spotify-reload.nu`):

```bash
curl -s http://127.0.0.1:9233/json/list | jq -r '.[] | "\(.type) \(.url) \(.webSocketDebuggerUrl)"'
echo '{"id":1,"method":"Runtime.evaluate","params":{"expression":"document.title"}}' | websocat -n1 <webSocketDebuggerUrl>
```

## Discord

No CDP. `configs/socials/discord/config/plugins/QuickshellVoiceStatus.plugin.js` writes voice state to
`$XDG_RUNTIME_DIR/quickshell-discord-voice.json` and runs JSON lines `{"cmd": ...}` from
`$XDG_RUNTIME_DIR/quickshell-discord-cmd`, unlinked on read: write a temp file and `mv` it. Commands: `toggleSelfMute`,
`toggleSelfDeaf`, `disconnect`. It reports a running `obs` as a streamer tool, which turns on Streamer Mode and with it
Discord's Twitch live check.
