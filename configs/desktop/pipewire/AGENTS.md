# desktop/pipewire

Extends the root `AGENTS.md` and the `configs/desktop/AGENTS.md`. The audio server, the headset eq as a filter
chain, and a loopback per app that carries its system volume.

## Layout

- `mod.nu`: copies the `pipewire-chain@.service` template and renders the `eq` chain into
  `~/.config/pipewire/eq.conf`, restarting it only when its config changed. The chain is its own client
  (`pipewire-chain@eq.service`), so stopping it leaves the server alone.
- `pro-x-2.txt`: the AutoEq preset for the Logitech PRO X 2 headset (verbatim from AutoEq; only the first line is read
  as Preamp). The options `eq_target` (the headset sink's node.name, unset: no eq) and `eq_preset` pick headset and
  preset; luca's machines set the PRO X 2 in their platform options.
- `app-loopback.lua`: a wpexec script run by `app-loopback.service` (copied to
  `~/.local/share/wireplumber/scripts/`), outside wireplumber, so a change to it never restarts the session manager.
  Option `app_loopbacks` (default on).

## Per-app loopbacks

Every app stream plays at its own level (the app's, e.g. spotify's slider, never touched) into `app.<key>` (an
Audio/Sink), whose `app.<key>.out` stream carries the system volume, mute and route to the device; wireplumber's
state-stream keeps those per app. A capture of the app's
own ports (obs's application capture) so never follows the system fader. Streams with a target of their own (obs
monitoring), notifications, filters and loopbacks keep their route. The quickshell mixer drives `app.<key>.out`
(`Audio.levelOf`) and routes it (`Audio.route`, by object.serial: state-stream saves a route only as a serial). A
mixer that moves the app stream itself (pavucontrol, wiremix) routes its loopback instead. The service's stop hands
each loopback's level to its streams (times their own, recorded in its state), its start splits them again, so a
restart keeps both; a stream that appears later is only routed, never leveled, and a loopback with no stream keeps
its own. The shell's cues play as `media.role` Notification, past the loopbacks. While
`dot.obs-listen` is set on the default metadata and obs runs, every loopback is muted
(`scripts/toggles/toggle-obs-listen.nu`, the mixer's HEAR System / OBS output switch).

## The eq

The headset AutoEq preset as a wireplumber smart filter (iir, no added latency, passive output) on `eq_target`.

## Conventions

- Native pipewire/wireplumber mechanisms only: filter chains, smart filters, module-loopback and wireplumber's Lua
  API, not easyeffects (per-stream, lsp-plugins).
- Never name a loopback node like its app: obs's application capture matches node.name, application.name and binary.
- No-op under WSL (wslg owns the audio).
