---
name: l-dotfiles-theming
description: How a wallpaper or theme switch recolors the system (wallust templates, theme verbs, themes/*.json, dot theme), adding a template or generator, and testing it on a dark and a light theme. Load when theming a new program or fixing colors.
---

# theming

`dot theme` recolours Luca's live desktop at once: ask before running it while he works, and put his wallpaper back
(Test).

## Flow

`dot theme <theme|wallpaper|random>` (`configs/core/wallust/wallpaper.nu`; no argument: wallpaper picker) is a pick. A
bare theme name is that theme: the palette of `themes/<theme>.json` (`wallust cs`), its wallpaper, its optional
`"font"` into `$XDG_CACHE_HOME/wal/font.json`. Anything else (a file name with its extension, a path, `random`) is a
wallpaper under the palette derived from it (`wallust run`), also when a theme names that file. The picker's Themes
tab picks by theme name, its Wallpapers tab by path. Every pick lands in `$XDG_STATE_HOME/dotfiles/theme-recent.json`
(the last four themes by name, four wallpapers by path; the picker's recents). The switch links
`$XDG_CACHE_HOME/wal/wallpaper`, then:

- A derived palette is conditioned before it applies (`condition-derived` in `palette.nu`, given the picture's 16
  colours from magick): color0 is the background itself, color8 a grey of the background's hue at 3:1, color4 and
  color12 trade places with the slot whose hue the picture holds when wallust put a foreign one there, and every slot
  reaches its `contrast-floors`. A theme applies as written.
- `$XDG_CACHE_HOME/wal/nvim_theme` records what is in effect: the theme's name, or `pywal` for a derived palette
  (`theme-get`). Every rerun without a pick (`wallpaper-set`: a font change, an apply) keeps it; only a home with no
  record falls back to the theme naming the wallpaper file.
- wallust renders `templates/wal/*` to `$XDG_CACHE_HOME/wal/<same name>` (pywal placeholders `{background}`,
  `{color0}`..). Other `[templates]` in `wallust.toml`: jinja at `templates/` (`{{color4}}`, `blend`),
  `colors-steam.css` for millennium, `omarchy-colors.toml` to `~/.local/state/omarchy/current/theme/`.
- Then every enabled module's `theme [cfg, wallpaper]` verb runs (`dot internal theme apply`), returning declarations.
  It reads `palette-load` (hex `bg`, `fg`, `c0`..`c15`, `light`, `bg_conditioned`) or `palette-rgb` (the 18 colours as
  rgb, for `palette.nu`'s conditioning, the one authority). Verbs run in parallel, in `meta.deps` order.
- Callers write the wallpaper and the palette into `$XDG_RUNTIME_DIR/theme.request`; `dot-theme.path` starts
  `dot-theme.service` for each waiting request; each run applies the newest one (`TimeoutStartSec=5min`, 60 s a verb).
  `--sync` waits for it.
- `dot internal theme apply` holds `theme.lock` in dot's state dir (`theme-locked`, `scripts/lib/cli.nu`), as do
  `dot module unlink|remove`, the other writers of a module's theme record; `dot apply` waits on the unit instead.
- quickshell recolours from `colors.json` through `Commons/Palette.js`, the JS port of `palette.nu`.

`palette.nu` also holds `RADIUS_PX`, `BORDER_PX`, `OPACITY_SHELL`, `OPACITY_SHELL_LIGHT` (shell, terminals, browser
chrome: `opacity-shell`) and `OPACITY_WINDOW` (an app Hyprland fades whole); modules write them into configs,
quickshell gets them in `Palette.js`. Live readers (qutebrowser, nvim) read `~/.config/dotfiles/style.json` (`style-json`), which holds only the keys they use: `radius_px`, `text_ratio`,
`light_luminance`, `white_text_luminance_max`.

Each theme names its other-mode partner in `"pair"` (`toggle-theme-mode.nu` flips to it by theme name; from a derived
palette it takes the nearest theme of the mode as the start and flips back to the wallpaper, derived again).
`themes.test.nu` checks the pair and contrast floors: fg, color4, color12 4.5:1 (dark also color7, color15), other
accents and color8 3:1. Every theme's wallpaper has a public copy in `wallpapers/`; names resolve from
`~/sync/wallpapers/` first (bought set, `wallpaper-import`), then `wallpapers/`.

## Add a template

1. `configs/core/wallust/templates/wal/colors-<tool>.<ext>` with the placeholders.
2. Point the program at `$XDG_CACHE_HOME/wal/colors-<tool>.<ext>` in its module's `link`.
3. Needs a reload: a `theme` verb that pokes it (`configs/desktop/kitty/mod.nu`).
4. A tool that reads its file by pywal convention, with no path in the repo: a row in `READERS` of
   `configs/core/wallust/readers.test.nu`, or a cleanup will drop the template as unused.

`dot apply core/wallust` renders a changed template at once (`theme-init`), so one apply shows the change.

## Add a generator

1. A `theme` verb in the program's `mod.nu` (`configs/core/btop/mod.nu`); dot discovers it.
2. Write under `$XDG_CACHE_HOME/wal/` or render the whole config with `file-text --generated`
   (`configs/core/herdr/mod.nu`); never into a file linked from the repo.
3. Must run after another module's verb: name that module in `meta.deps`.
4. An editor or diff viewer takes its syntax, diagnostic, diff and surface colours from `editor-roles`
   (`configs/core/wallust/editor.nu`), given the background it draws on, as nvim, zed, emacs and delta do.
5. Conditioning changes go into `palette.nu` and `Palette.js` (`palette.nu js --write`); `dot test check` compares
   both on a dark and a light palette.

## Test

After his yes:

```bash
cat "$XDG_CACHE_HOME/wal/nvim_theme"; dot internal theme get   # remember the theme, or for pywal the wallpaper
dot theme --sync void
dot theme --sync gruvbox-light
dot theme --sync <remembered theme, or for pywal the remembered path>
```

Output in `journalctl --user -u dot-theme.service`. Check `$XDG_CACHE_HOME/wal/<file>`, the look (a screenshot,
`l-dotfiles-gui-testing`) and light-theme contrast. `git status` stays clean. A full user run reruns the switch when
`configs/core/wallust` or `themes/` changed (stamp `$XDG_CACHE_HOME/wal/.theme-stamp`); any apply
reruns the `theme` verb of each module it applied.
