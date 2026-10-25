---
name: l-dotfiles-theming
description: How a wallpaper or theme switch recolors the system (wallust templates, theme verbs, themes/*.json, dot theme), adding a template or generator, and testing it on a dark and a light theme. Load when theming a new program or fixing colors.
---

# theming

## Flow

`dot theme <wallpaper|path|random>` (`configs/core/wallust/wallpaper.nu`; no argument opens the picker) takes a wallpaper file
name, not a theme name: a theme is picked through its wallpaper, `dot theme "$(jq -r .wallpaper themes/<t>.json)"`.
It links `~/.cache/wal/wallpaper`, then:

- A wallpaper named by a `themes/<theme>.json` (`"wallpaper"` field) applies that hand-made palette
  (`wallust cs -s --wallpaper <file> <theme>`, plus its optional `"font"` into `~/.cache/wal/font.json`); any other
  wallpaper derives one (`wallust run -s <file>`). Either way it also writes `~/.cache/wal/nvim_theme`.
- wallust renders every file of `configs/core/wallust/templates/wal/` to `~/.cache/wal/<same name>` (pywal
  placeholders `{background}`, `{foreground}`, `{color0}` to `{color15}`). The other `[templates]` entries in
  `wallust.toml`: jinja templates at the `templates/` root (`{{color4}}`, filters such as `blend`) to
  `~/.cache/wal/`, `colors-steam.css` to Steam's millennium theme, `omarchy-colors.toml` to
  `~/.local/state/omarchy/current/theme/`.
- Then every enabled module's `theme` verb runs (`dot internal theme apply`): `export def theme [cfg: record, wallpaper:
  string]` in its `mod.nu`, returning declarations like `link`. It reads the palette with `palette-load` (`bg`, `fg`,
  `c0` to `c15`, `light`, `bg_conditioned`) or `configs/core/wallust/palette.nu` directly, the one conditioning
  authority (contrast, tone map, readable text).
- Every caller writes the wallpaper path into `$XDG_RUNTIME_DIR/theme.request`; `dot-theme.path` (`PathExists`)
  starts `dot-theme.service` (`dot internal theme serve`) while that file exists, and re-checks when a run ends, so
  a request written as a run finishes starts the next one. The run moves the request aside and applies the newest
  one until none is left, skipping the verbs of a palette a newer request replaced; `TimeoutStartSec=3min` ends a run
  a hung verb holds. `--sync` starts the unit itself and waits until no request is left. The verbs run in parallel; `THEME_ORDERED` in `scripts/lib/internal.nu` names the few that run
  last and in order (spotify before discord). Live pokes are theme verbs too (hyprland reload,
  kitty, ghostty, tmux, nvim, emacs, pywalfox). quickshell recolours itself from `colors.json` through
  `Commons/Palette.js`, the JS port of `palette.nu`.

Shape and glass come from `palette.nu` too: `RADIUS_PX`, `BORDER_PX`, `OPACITY_WINDOW` (hyprland's window rule),
`OPACITY_SURFACE` (terminal backgrounds, shell panels), `OPACITY_BAR` (the bar, firefox's toolbars). A module writes
them into its program's config (`style.lua`, `dotfiles-style.css`, `ROUNDNESS`), quickshell reads them from
`Palette.js`, and a program that reads config live (qutebrowser, nvim) reads `~/.config/dotfiles/style.json`.

Most families have a light theme (`catppuccin-latte`, `rose-pine-dawn`, `alucard`, ...) and some a soft one
(`gruvbox-*-soft`, `everforest-*-soft`). Every theme names its family's theme of the other mode in `"pair"` (a light
one pairs back), which `toggle-theme-mode.nu` flips to; `themes.test.nu` checks it, so a new
theme needs one. It also holds every theme's raw palette to contrast floors on its background (foreground, color4 and
color12 4.5:1, on a dark theme also color7 and color15; the other accents and color8 3:1), since templates use those
colours unconditioned. Every theme's wallpaper has a public copy in `wallpapers/`, so themes work without the
bought set; a name resolves from `~/sync/wallpapers/` first (the bought ones, imported with `wallpaper-import`,
synced by syncthing), then `wallpapers/` (`configs/core/wallust/wallpaper-list.nu`).

## Add a template (a program reads a color file)

1. Add `configs/core/wallust/templates/wal/colors-<tool>.<ext>` using the placeholders.
2. Point the program at `~/.cache/wal/colors-<tool>.<ext>` from its module's `link` verb.
3. If the program needs a reload, add a `theme` verb that pokes it (see `configs/desktop/kitty/mod.nu`).

## Add a generator (needs computed colors or another format)

1. Add a `theme` verb to the program's `mod.nu` (see `configs/core/btop/mod.nu`). Adding the verb is the whole
   change: dot discovers it.
2. Write the output under `~/.cache/wal/`, or render the program's whole config with `file-text --generated` (see
   `configs/core/herdr/mod.nu`); never into a file the module links from the repo, which would change a tracked file
   on every switch.
3. Only if it must run after another theme verb, add it to `THEME_ORDERED`.
4. A change to the conditioning goes into `palette.nu` and `Commons/Palette.js` (a constant: `palette.nu js --write`);
   `dot test check` compares the two on a dark and a light palette.

## Test

```bash
dot internal theme get                                         # remember the current wallpaper
dot theme --sync "$(jq -r .wallpaper themes/void.json)"
dot theme --sync "$(jq -r .wallpaper themes/gruvbox-light.json)"
dot theme --sync <remembered path>
```

`--sync` waits for the unit's run; `journalctl --user -u dot-theme.service` has its output. After each: check `~/.cache/wal/<your file>`, the program's look
(screenshot on a headless output, skill `l-dotfiles-gui-testing`), and contrast on the light theme. `git status` stays clean: a switch writes nothing in the
repo. A full user run (no module arguments) reruns the whole switch when anything under `configs/core/wallust`,
`themes/`, or any `mod.nu` changed, tracked or untracked (stamp
`~/.cache/wal/.theme-stamp`); any apply reruns the `theme` verb of each module it applied.
