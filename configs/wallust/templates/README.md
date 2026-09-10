# pywal templates, rendered by wallust

Copied verbatim from `/usr/lib/python3.14/site-packages/pywal/templates/` —
only the 8 files this repo actually reads, not pywal16's full 56. wallust
renders them with `pywal = true` (its pywal-syntax compatibility mode), so
every consumer keeps finding the same `~/.cache/wal/*` paths in the same
formats.

`colors-spicetify.ini` is the exception: it is not a pywal16 built-in. It
came from `~/.config/wal/templates/`, where it was **untracked** and would
not have survived a fresh machine setup. Also kept at
`configs/spotify/wal-templates/` as the canonical copy.

## One local edit, and why it mattered

pywal's `colors.json` template starts with `"checksum": "{checksum}"`.
wallust has no `checksum` variable, so that template — and **only** that
template — failed with `Missing variable: checksum` while the other seven
rendered fine.

That is the worst possible file to lose. `colors.json` is what
`quickshell/Commons/Color.qml` and pywalfox both read. The failure is a
warning, not an error: wallust exits 0, seven files update, and the stale
`colors.json` sits there looking plausible. The shell would simply have kept
the old palette forever with nothing obviously broken.

The line is dropped here. Nothing in this repo reads `checksum`; pywalfox
needs only `colors` and `wallpaper`, both still present.

**If you add a template later, check it actually rendered** — do not trust
wallust's exit code.
