---
name: l-dotfiles-theming
description: How a wallpaper or theme switch recolors the system (wallust templates, theme verbs, themes/*.json, dot theme), adding a template or generator, and testing it on a dark and a light theme. Load when theming a new program or fixing colors.
---

# theming

## Flow

`dot theme <wallpaper|path|random>` (`configs/core/wallust/wallpaper.nu`; no argument: picker) takes a wallpaper, not a
theme name: `dot theme "$(jq -r .wallpaper themes/<t>.json)"`. It links `~/.cache/wal/wallpaper`, then:

- A wallpaper named in a `themes/<theme>.json` applies that palette (`wallust cs`, plus its optional `"font"` into
  `~/.cache/wal/font.json`); any other derives one (`wallust run`). Both write `~/.cache/wal/nvim_theme`.
- wallust renders `templates/wal/*` to `~/.cache/wal/<same name>` (pywal placeholders `{background}`, `{color0}`..).
  Other `[templates]` in `wallust.toml`: jinja at `templates/` (`{{color4}}`, `blend`), `colors-steam.css` for
  millennium, `omarchy-colors.toml` to `~/.local/state/omarchy/current/theme/`.
- Then every enabled module's `theme [cfg, wallpaper]` verb runs (`dot internal theme apply`), returning declarations.
  It reads `palette-load` (`bg`, `fg`, `c0`..`c15`, `light`, `bg_conditioned`) or `palette.nu`, the one conditioning
  authority. Verbs run in parallel; `THEME_ORDERED` (`scripts/lib/internal.nu`) runs a few last, in order.
- Callers write the wallpaper into `$XDG_RUNTIME_DIR/theme.request`; `dot-theme.path` starts `dot-theme.service`, which
  applies the newest request until none is left (`TimeoutStartSec=3min`). `--sync` waits for it.
- quickshell recolours from `colors.json` through `Commons/Palette.js`, the JS port of `palette.nu`.

`palette.nu` also holds `RADIUS_PX`, `BORDER_PX`, `OPACITY_WINDOW`, `OPACITY_SURFACE`, `OPACITY_BAR`; modules write them
into configs, live readers (qutebrowser, nvim) use `~/.config/dotfiles/style.json`.

Each theme names its other-mode partner in `"pair"` (`toggle-theme-mode.nu` flips to it). `themes.test.nu` checks the
pair and contrast floors: fg, color4, color12 4.5:1 (dark also color7, color15), other accents and color8 3:1. Every
theme's wallpaper has a public copy in `wallpapers/`; names resolve from `~/sync/wallpapers/` first (bought set,
`wallpaper-import`), then `wallpapers/`.

## Add a template

1. `configs/core/wallust/templates/wal/colors-<tool>.<ext>` with the placeholders.
2. Point the program at `~/.cache/wal/colors-<tool>.<ext>` in its module's `link`.
3. Needs a reload: a `theme` verb that pokes it (`configs/desktop/kitty/mod.nu`).

## Add a generator

1. A `theme` verb in the program's `mod.nu` (`configs/core/btop/mod.nu`); dot discovers it.
2. Write under `~/.cache/wal/` or render the whole config with `file-text --generated` (`configs/core/herdr/mod.nu`);
   never into a file linked from the repo.
3. Must run after another verb: add it to `THEME_ORDERED`.
4. Conditioning changes go into `palette.nu` and `Palette.js` (`palette.nu js --write`); `dot test check` compares
   both on a dark and a light palette.

## Test

```bash
dot internal theme get                                         # remember the current wallpaper
dot theme --sync "$(jq -r .wallpaper themes/void.json)"
dot theme --sync "$(jq -r .wallpaper themes/gruvbox-light.json)"
dot theme --sync <remembered path>
```

Output in `journalctl --user -u dot-theme.service`. Check `~/.cache/wal/<file>`, the look (headless screenshot,
`l-dotfiles-gui-testing`) and light-theme contrast. `git status` stays clean. A full user run reruns the switch when
`configs/core/wallust`, `themes/` or any `mod.nu` changed (stamp `~/.cache/wal/.theme-stamp`); any apply reruns the
`theme` verb of each module it applied.
