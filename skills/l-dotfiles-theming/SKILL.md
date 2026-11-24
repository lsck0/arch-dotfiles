---
name: l-dotfiles-theming
description: "How dot theme and wallpaper switches recolor the system: wallust templates, module theme verbs, themes/*.json, palette.nu conditioning, dot-theme.service. Load when theming a new program, fixing colors or contrast, or adding a theme. Switching the theme for Luca: l-dotfiles-desktop-control."
---

# theming

`dot theme` recolours Luca's live desktop at once: ask before running it while he works, and put his theme back
(Test).

## How a switch runs

`dot theme <theme|wallpaper|random>` (`configs/core/wallust/scripts/wallpaper.nu`; no argument: the picker). A bare
theme name applies `themes/<theme>.json` as written (`wallust cs`), its wallpaper and its optional `"font"`
(`$XDG_CACHE_HOME/wal/font.json`). Anything else (a file name with extension, a path, `random`) is a wallpaper under a
palette derived from it (`wallust run`), also when a theme names that file. Names resolve from `~/sync/wallpapers/`
(bought, `wallpaper-import`), then `wallpapers/`. Picks land in `$XDG_STATE_HOME/dotfiles/theme-recent.json`.

1. A derived palette is conditioned (`condition-derived` in `palette.nu`): color0 is the background, color8 a grey of
   its hue at 3:1, color4 and color12 swap with the slot holding the picture's hue when wallust put a foreign one
   there, every slot reaches its `contrast-floors`.
2. `$XDG_CACHE_HOME/wal/nvim_theme` records the theme name, or `pywal` for a derived palette (`theme-get`); a rerun
   without a pick (`wallpaper-set`) keeps it.
3. wallust renders `templates/wal/*` to `$XDG_CACHE_HOME/wal/<same name>` (pywal `{background}`, `{color0}`..) and the
   other `[templates]` of `wallust.toml` (jinja in `config/templates/`: `{{color4}}`, `blend`).
4. `dot internal theme apply` runs every enabled module's `theme [cfg, wallpaper]` verb, in parallel in `meta.deps`
   order (`THEME_VERB_TIMEOUT` in `scripts/lib/pipeline.nu`). A verb reads `palette-load` (hex `bg`, `fg`,
   `c0`..`c15`, `light`) or `palette-rgb`.

Callers write a request to `$XDG_RUNTIME_DIR/theme.request`; `dot-theme.path` starts `dot-theme.service`, which applies
the newest; `--sync` waits. The run holds `theme.lock` (`theme-locked`, `scripts/lib/cli.nu`). A full user run reruns
the switch when `configs/core/wallust` or `themes/` changed (stamp `$XDG_CACHE_HOME/wal/.theme-stamp`); any apply reruns
the `theme` verb of each module it applied.

`palette.nu` is the one authority: conditioning and the constants `RADIUS_PX`, `BORDER_PX`, `OPACITY_SHELL`,
`OPACITY_SHELL_LIGHT` (`opacity-shell`), `OPACITY_WINDOW`. Quickshell recolours from `colors.json` through
`Commons/Palette.js`, its JS port; live readers (qutebrowser, nvim) read `~/.config/dotfiles/style.json`
(`style-json`).

## Add a template

1. `configs/core/wallust/config/templates/wal/colors-<tool>.<ext>` with the placeholders.
2. Point the program at `$XDG_CACHE_HOME/wal/colors-<tool>.<ext>` in its module's `link`.
3. Needs a reload: a `theme` verb that pokes it (`configs/desktop/kitty/mod.nu`).
4. A tool that finds its file by pywal convention, with no path in the repo: a row in `READERS` of
   `configs/core/wallust/readers.test.nu`, or cleanup drops the template as unused.

`dot apply core/wallust` renders a changed template at once.

## Add a generator

1. A `theme` verb in the program's `mod.nu` (`configs/core/btop/mod.nu`); dot discovers it.
2. Write under `$XDG_CACHE_HOME/wal/` or render the whole config with `file-text --generated`
   (`configs/core/herdr/mod.nu`); never into a file linked from the repo.
3. Must run after another module's verb: name that module in `meta.deps`.
4. An editor or diff viewer takes syntax, diagnostic, diff and surface colours from `editor-roles`
   (`configs/core/wallust/scripts/editor.nu`) for the background it draws on, as nvim, zed, emacs and delta do.
5. A conditioning change goes into `palette.nu`, then `configs/core/wallust/scripts/palette.nu js --write`
   regenerates `Palette.js`; `dot test check` compares both on a dark and a light palette.

## Add a theme

`themes/<name>.json` names its other-mode partner in `"pair"` (`toggle-theme-mode.nu` flips to it) and a wallpaper with
a public copy in `wallpapers/`. `themes/themes.test.nu` checks the pair and the contrast floors: fg, color4, color12
4.5:1 (dark also color7, color15), other accents and color8 3:1.

## Test

After Luca's yes:

```bash
cat "$XDG_CACHE_HOME/wal/nvim_theme"; dot internal theme get   # remember the theme, or for pywal the wallpaper
dot theme --sync void
dot theme --sync gruvbox-light
dot theme --sync <remembered theme, or for pywal the remembered path>
```

1. Read `journalctl --user -u dot-theme.service` for errors.
2. Check `$XDG_CACHE_HOME/wal/<file>`, the look (a screenshot, `l-dotfiles-gui-testing`) and light-theme contrast.
3. `git status` stays clean.
