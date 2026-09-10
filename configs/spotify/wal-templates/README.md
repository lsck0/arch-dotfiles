# Untracked-by-accident pywal template, rescued 2026-09-03

`colors-spicetify.ini` lived **only** at
`~/.config/wal/templates/colors-spicetify.ini` on this machine. It is not
shipped by `python-pywal16` (its built-in template dir has no
`colors-spicetify`), and it was not tracked anywhere in this repo — almost
certainly dropped there by `pywal-spicetify`'s own installer.

That made it invisible to every grep of this repo and guaranteed to vanish
on a fresh machine setup, taking Spotify theming with it. Copied here so it
survives.

The live chain: `switch-wallpaper.sh` runs `pywal-spicetify wal`, which reads
the *rendered* `~/.cache/wal/colors-spicetify.ini` (produced from this
template) and writes `configs/spotify/color.ini` through the symlink at
`~/.config/spicetify/Themes/wal/color.ini`.

**Not yet wired into install.sh** — restoring it on a new machine currently
means copying it back to `~/.config/wal/templates/`. It is also the file
`research/pywal-wallust-migration.md` §0/§3 says to register as a wallust
template if that migration ever happens.
