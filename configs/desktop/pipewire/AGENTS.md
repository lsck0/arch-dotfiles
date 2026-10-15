# desktop/pipewire

Extends the root `AGENTS.md` and the `configs/desktop/AGENTS.md`. The audio server and the headset eq, as a filter
chain. Streams take wireplumber's default routing to the default sink.

## Layout

- `mod.nu`: copies the `pipewire-chain@.service` template and renders the `eq` chain into
  `~/.config/pipewire/eq.conf`, restarting it only when its config changed. The chain is its own client
  (`pipewire-chain@eq.service`), so stopping it leaves the server alone.
- `pro-x-2.txt`: the AutoEq preset for the Logitech PRO X 2 headset (verbatim from AutoEq; only the first line is read
  as Preamp). The options `eq_target` (the headset sink's node.name, unset: no eq) and `eq_preset` pick headset and
  preset; luca's machines set the PRO X 2 in their platform options.

## The eq

The headset AutoEq preset as a wireplumber smart filter (iir, no added latency, passive output) on `eq_target`.

## Conventions

- Native pipewire/wireplumber mechanisms only: filter chains and smart filters, not easyeffects (per-stream,
  lsp-plugins).
- No-op under WSL (wslg owns the audio).
