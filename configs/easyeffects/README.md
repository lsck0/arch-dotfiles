# easyeffects

Empty scaffold. `link.sh` symlinks the repo's `input/` (mic) and `output/`
(playback) preset dirs into `~/.config/easyeffects/`, so any preset you save in
the app is tracked here. No presets committed yet.

## Configure

1. Launch `easyeffects`, build a preset (output EQ, or input mic noise
   suppression via the "Noise Reduction"/`pw-rnnoise` effect), save it. It lands
   in `input/` or `output/` here.
2. Commit the preset JSON.
