---
name: l-dotfiles-theming
description: How a wallpaper or theme switch recolors the system (wallust templates, theme verbs, themes/*.json, dot theme), adding a template or generator, and testing it on a dark and a light theme. Load when theming a new program or fixing colors.
---

# theming

## Flow

`dot theme set <name|path>` (`scripts/lib/wallpaper.nu`) links `~/.cache/wal/wallpaper`, then:

- A wallpaper named by a `configs/core/themes/<theme>.json` (`"wallpaper"` field) applies that hand-made palette
  (`wallust cs -s <theme>`, plus its optional `"font"` through `toggle-font.nu set`); any other wallpaper derives one
  (`wallust run -s <file>`).
- wallust renders every file of `configs/core/wallust/templates/wal/` to `~/.cache/wal/<same name>`
  (`wallust.toml`, `{background}`, `{foreground}`, `{color0}` to `{color15}`).
- Then every enabled module's `theme` verb runs (`dot theme apply`): `export def theme [cfg: record, wallpaper:
  string]` in its `mod.nu`, returning declarations like `link`. It reads the palette with `palette-load` (`bg`, `fg`,
  `c0` to `c15`, `light`, `bg_conditioned`) or `configs/core/wallust/palette.nu` directly, the one conditioning
  authority (contrast, tone map, readable text).
- The verbs run in the background outside the switch's lock; `THEME_FOREGROUND` in `scripts/dot.nu` names the few
  that must run in order under it (spotify before discord, gtk). Live pokes are theme verbs too (hyprland reload,
  kitty, ghostty, tmux, nvim, emacs, pywalfox). quickshell recolours itself from `colors.json` through
  `Commons/Palette.js`, the JS port of `palette.nu`.

Light themes: `ayu-light`, `gruvbox-light`, `solarized-dawn`. `gruvbox-light`'s wallpaper is in
`secrets/wallpapers/` and needs unlocked secrets.

## Add a template (a program reads a color file)

1. Add `configs/core/wallust/templates/wal/colors-<tool>.<ext>` using the placeholders.
2. Point the program at `~/.cache/wal/colors-<tool>.<ext>` from its module's `link` verb.
3. If the program needs a reload, add a `theme` verb that pokes it (see `configs/desktop/kitty/mod.nu`).

## Add a generator (needs computed colors or another format)

1. Add a `theme` verb to the program's `mod.nu` (see `configs/core/btop/mod.nu`). Adding the verb is the whole
   change: dot discovers it.
2. Write the output under `~/.cache/wal/`. Writing into a file the module links from the repo changes a tracked
   file on every switch (VSCodium settings, herdr config, spicetify `color.ini`, KDE colors already do); avoid it
   for new tools.
3. Only if it must run in order or rewrites a file a second switch would race, add it to `THEME_FOREGROUND`.
4. A change to the conditioning goes into `palette.nu` and `Commons/Palette.js` (a constant: `palette.nu js --write`);
   `dot test check` compares the two on a dark and a light palette.

## Test

```bash
dot theme get                                                      # remember the current wallpaper
dot theme set --sync "$(jq -r .wallpaper configs/core/themes/void.json)"
dot theme set --sync "$(jq -r .wallpaper configs/core/themes/gruvbox-light.json)"
dot theme set --sync <remembered path>
```

`--sync` waits for the background verbs. After each: check `~/.cache/wal/<your file>`, the program's look
(screenshot with `grim`), and contrast on the light theme. Then `git status`: revert nothing the switch rewrote,
the restore step puts it back. `dot link` reruns the switch itself when anything under `configs/core/wallust`,
`configs/core/themes`, a tracked `mod.nu` or `scripts/lib/wallpaper.nu` changed.
