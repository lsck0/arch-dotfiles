# desktop/pipewire

Extends the root `AGENTS.md` and the `configs/desktop/AGENTS.md`. The audio server, its role-based lanes and the
headset eq, as filter chains.

## Layout

- `mod.nu`: copies `roles.conf` into `pipewire-pulse.conf.d` and the `pipewire-chain@.service` template, and renders
  the `lanes` and `eq` chains into `~/.config/pipewire/<chain>.conf`, restarting a chain only when its config changed.
  Each chain is its own client (`pipewire-chain@<chain>.service`), so stopping one leaves the server and the other
  alone.
- `roles.conf`: maps pulse apps to a `media.role` (Firefox/Chromium to Movie, Discord/ZapZap to Communication); later
  rules win. Apps without a claimed role stay direct.
- `pro-x-2.txt`: the AutoEq preset for the Logitech PRO X 2 headset (verbatim from AutoEq; only the first line is read
  as Preamp). The options `eq_target` (the headset sink's node.name, unset: no eq) and `eq_preset` pick headset and
  preset; luca's machines set the PRO X 2 in their platform options.

## The chains

- `lanes`: a lane is a virtual sink claiming media roles (`device.intended-roles`); wireplumber routes each role into
  its lane. `media` (Music, Movie) and `voice` (Communication, Phone). Each lane does per-role loudness leveling:
  `in -> ebur128 -> gain -> out`, gain driven by gated integrated LUFS toward `TARGET_LUFS=-18.0`, clamped
  (`GAIN_MIN=0.25`, `GAIN_MAX=2.0`). The leveler switch (amount) and the lane fader are the quickshell audio panel's
  contract over pw-cli/pw-dump; the monitor is before the fader so OBS captures the playback side (`creating/obs`).
  Unclaimed roles (games, system sounds) stay on the hardware sink, zero added latency.
- `eq`: the headset AutoEq preset as a wireplumber smart filter (iir, no added latency, passive output). The audio
  panel's eq switch owns `pipewire-chain@eq.service`.

## Conventions

- Native pipewire/wireplumber mechanisms only: filter chains and smart filters, not easyeffects (per-stream,
  lsp-plugins) or ffmpeg loudnorm (lookahead latency, not realtime safe).
- No-op under WSL (wslg owns the audio).
- `roles.conf` is read at pipewire-pulse start; the link verb does not restart it (would drop a live call).
