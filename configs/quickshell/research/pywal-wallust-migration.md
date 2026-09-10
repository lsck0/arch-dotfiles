# pywal → wallust: full migration plan

Outside the numbered SPEC sequence (00–08 + `ROADMAP.md`), same as
`ryoku-patterns.md`. Written 2026-09-02 after the owner rejected a lighter
"wallust in pywal-compat mode, touch nothing else" proposal made earlier in
the same conversation and asked for a plan to **fully replace pywal**, with
explicit coverage of every consumer — "from discord to firefox etc."

**STATUS 2026-09-03 — DONE. wallust is now the colour engine.** pywal is no
longer invoked anywhere. What actually happened, including where this plan
was wrong:

- **Installed `wallust-git` from chaotic-aur** — 4.0.0-alpha, a major version
  ahead of the 3.5.2 this plan was written against. Its config schema matches
  what §5 describes, including the `pywal = true` compat mode, so the plan
  held up.
- **Track A's byte-identical premise does NOT hold, and this was verified by
  diffing, not assumed.** Against the same wallpaper, wallust's `wal`
  backend (ImageMagick, pywal's own extraction) still produced bg `#000000` /
  fg `#CAD8C5` where pywal16 produced `#0b1019` / `#c2c3c5`. pywal16 is a
  16-colour *fork* that post-processes its palette; matching its output would
  mean reimplementing those adjustments, not just borrowing its extraction
  step. §6/§8's plan to use `backend = "wal"` as a risk-isolating no-op was
  therefore pointless, and `fastresize` + `salience` (wallust's own
  recommended defaults) were used instead.
- **What DID carry over is the thing that mattered: the schema.** All 8
  consumed templates render to the same `~/.cache/wal/` paths in the same
  formats. **Zero downstream files were changed** — quickshell, hyprland,
  kitty, ghostty, zsh, hyprlock, discord, spotify, oomox/GTK, KDE, zed,
  vscodium, herdr and pywalfox all still work untouched. Verified after a
  real wallpaper switch that every one of them shows the new palette.
- **One template silently failed, and it was the worst possible one.**
  pywal's `colors.json` template opens with `"checksum": "{checksum}"`;
  wallust has no such variable, so that file — and only that file — failed
  with `Missing variable: checksum` while the other seven rendered fine.
  wallust still exits 0. `colors.json` is what quickshell's `Color.qml` and
  pywalfox both read, so the shell would have kept a stale palette forever
  with nothing visibly broken. The line is dropped from the template; nothing
  here reads it. **Do not trust wallust's exit code — check that files
  actually rendered.**
- **A config-path trap:** `template =` is relative to
  `<config-dir>/templates/`, **not** to `<config-dir>` as the shipped sample
  config's wording implies. `'templates/wal/'` resolves to
  `.../templates/templates/wal/` and renders nothing, with a warning rather
  than an error.
- **Palette values shifted system-wide, as §8 predicted.** Unavoidable — it
  is a different engine. The UI overhaul landed first, which turned out to
  matter: wallust handed the shell a near-black `#030508` background (HSV
  value 0.031), and `Color.qml`'s new `toneMap()` lifted it into the legible
  band automatically. On the old code that would simply have been a void.
- **Phase 1 (the untracked spicetify template) was done first**, and is now
  tracked twice: `configs/spotify/wal-templates/` as the canonical copy and
  `configs/wallust/templates/wal/` as the rendered source.
- **Rollback is still a one-line revert** of `switch-wallpaper.sh` back to
  `wal -i`; `python-pywal16` remains installed transitively via
  `pywal-spicetify`, exactly as §8 advises for the bake-in period.
- **Two §1 inventory rows were already stale:** `configs/walker/...` is gone
  (walker removed 2026-09-02, roadmap Phase 7).

Everything below is the original plan as written.

**This plan directly reverses two things**This plan directly reverses two things this repo's own docs currently call
settled:** `ROADMAP.md`'s Ground rule #3, *"Theming is pywal-only... Never
hardcode a color, pull from `Commons/Color.qml`"* (pywal-only is the settled
part, not the "don't hardcode" part), and `00-index.md`'s "theming is
pywal-only... there is no multi-theme layer and one should not be added." If
this plan is adopted, both need a one-line edit to say wallust instead of
pywal — noted again in §7. Nothing in this document has been applied to any
config. Read-only research.

---

## 0. Ground truth: what's actually installed today

This is not the archived, unmaintained `dylanaraps/pywal`. `pacman -Qi`
shows **`python-pywal16` 1:3.8.15-1** — `eylles/pywal16`, an actively
maintained 16-color fork — `Provides: pywal python-pywal`. It is **not**
declared anywhere in `install.sh`; it's pulled in transitively as a
dependency of the AUR package `pywal-spicetify` (`Required By:
pywal-spicetify`). This matters for §7 (package changes): there is no
`install.sh` line to delete for pywal itself, only for `pywal-spicetify` and
`python-pywalfox` if those get replaced too.

pywal16 ships **56 built-in templates** (`/usr/lib/python3.14/site-packages/
pywal/templates/`) — far more than stock pywal ever had, including
`ghostty.conf`, `colors-zed.json`, `colors-yasb.css`, `colors.qml`, and
others that read as community-contributed. Every one of them is rendered
into `~/.cache/wal/` on each `wal -i` run (confirmed via `ls -la
~/.cache/wal/`, 60+ files present right now). One of them, `colors.qml`, is
dead weight — nothing in `configs/quickshell/` reads it; `Commons/Color.qml`
parses `colors.json` directly via `FileView` (`configs/quickshell/Commons/
Color.qml:18,97-99`). No action needed there either way.

**One critical local-only dependency, invisible to any repo grep:**
`~/.config/wal/templates/colors-spicetify.ini` exists on this machine and is
**not tracked by git** — it's not shipped by pywal16 (confirmed: no
`colors-spicetify` in pywal16's built-in template dir) and not present
anywhere under `configs/`. It was almost certainly dropped there by
`pywal-spicetify`'s own installer. Its content:

```
accent             = {color0.strip}
accent-active      = {color2.strip}
accent-inactive    = {color3.strip}
banner             = {color4.strip}
border-active      = {foreground.strip}
...
```

**Before touching anything, copy this file into the repo** (e.g.
`configs/spotify/wal-templates/colors-spicetify.ini`) or it will not survive
a fresh machine setup regardless of which color tool generates it.

## 1. Full consumer inventory

Every current pywal dependency in this repo, verified by reading the file
(not assumed from filename). "Trigger" = something that invokes a binary;
everything else only *consumes* generated output.

| File | Mechanism | wallust path |
| --- | --- | --- |
| `scripts/switch-wallpaper.sh:11` | **Trigger.** `wal -i "$file"` | `wallust run "$file"` |
| `scripts/switch-wallpaper.sh` (rest of `set_wallpaper()`) | Reads `~/.cache/wal/{colors,colors-rgb,colors.json,wallpaper}` via `sed`/symlink; also writes `~/.cache/wal/wallpaper` and `wallpaper_path` itself, **not** pywal output | No change needed if those cache files keep the same shape (§5) |
| `configs/quickshell/Commons/Color.qml:18,97-99` | Reads `~/.cache/wal/colors.json` via `FileView`, JSON keys `special.{background,foreground,cursor}` + `colors.color0..15` | Unchanged if wallust's `colors.json` template preserves this exact schema |
| `configs/hyprland/wal_colors.lua` | Reads `~/.cache/wal/colors`, 16 lines of `#rrggbb`, derives `background=color0`, `foreground=color7` (a repo-specific convention, not from `colors.json`'s `special` block) | Unchanged if the `colors` file (16 lines, same order) is preserved |
| `configs/kitty/kitty.conf:1` | `include ~/.cache/wal/colors-kitty.conf` | Unchanged if that file is preserved |
| `configs/ghostty/config:1` | `config-file=~/.cache/wal/ghostty.conf` | Unchanged if that file is preserved (pywal16-specific template — see §4) |
| `configs/zsh/zshrc:1` | `source ~/.cache/wal/colors.sh` (shell vars: `$background`, `$color0`..`$color15`) | Unchanged if preserved |
| `scripts/themed-bmenu.sh` | Sources the same `colors.sh` | Unchanged if preserved |
| `scripts/generate-editor-themes.sh` | Reads `~/.cache/wal/colors.json` via `jq`, writes `configs/zed/themes/pywal.json` + VSCodium `settings.json` + herdr's marker-delimited `[theme.custom]` block | Unchanged — pure JSON-key consumer |
| `scripts/generate-kde-theme.sh` | Reads `colors.json` via `jq`, writes through `kdeglobals`/`plasma-...appletsrc` symlinks via `kwriteconfig6` | Unchanged |
| `scripts/switch-wallpaper.sh` (oomox block) | `themix-multi-export ... ~/.cache/wal/colors-oomox` (GTK/Qt theme, via oomox's own `pywal` base16 plugin at `/opt/oomox/plugins/base16/templates/pywal/`) | Unchanged if `colors-oomox` file preserved — **oomox itself has a hardcoded "pywal" plugin name, but only reads the file, not the binary; harmless label** |
| `configs/hyprland/hyprlock.conf` + `switch-wallpaper.sh` sed block | 5 `sed -i` calls pulling specific lines out of `colors-rgb` (positional: line 1 = background, line 2 = foreground/accent, lines 3-5 = colors 1-3) | Unchanged if `colors-rgb` line order preserved |
| `configs/walker/themes/custom/style.css` + `switch-wallpaper.sh` sed block | 3 `sed -i` calls, lines 1-3 of `colors` (bare hex, no `#`... confirm format, currently `#rrggbb` per `wal_colors.lua`'s parser) | Unchanged if preserved |
| `configs/discord/wal.theme.css` + `switch-wallpaper.sh` sed block | 6 `sed -i` calls setting 3 CSS custom properties, all sourced from **`colors-rgb`** lines 1-2 only (not templated, hand-rolled) — see §2 | Unchanged if preserved |
| `configs/spotify/color.ini` | **Not** touched by any script here — regenerated in place (through the `~/.config/spicetify/Themes/wal/color.ini` symlink, `configs/spotify/link.sh:9`) by the **compiled `pywal-spicetify` binary**, triggered by `switch-wallpaper.sh`'s `pywal-spicetify wal &` | See §3 |
| `configs/plasma/kdeglobals:137` | `ColorScheme=pywal` — an arbitrary label string in a KDE ini, cosmetic only | Optional rename, not functional |
| `configs/nvim/lua/plugins/ui.lua:5-8` | `pywal.nvim` plugin spec, **entirely commented out** | Not a live dependency — skip |
| `toggles/toggle-font.sh:32` | References `configs/discord/wal.theme.css` path for a font substitution, not a color one | Unaffected either way |
| `install.sh` | No `pywal`/`python-pywal16` package line (see §0) | Add wallust's package line; leave existing lines alone unless §7's optional replacements are taken |

## 2. Discord — BetterDiscord

`configs/discord/wal.theme.css` is symlinked in by `configs/discord/
link.sh` (note: it's `cp`'d, not `ln`'d, per that file's own comment —
"BetterDiscord cannot see file changes through a symlink" — so **the
tracked repo copy and the live copy diverge the moment `switch-wallpaper.sh`
edits `~/.config/BetterDiscord/themes/wal.theme.css` directly**; the repo's
`wal.theme.css` is only the initial seed). The live file gets exactly 3 CSS
custom properties patched via `sed`, sourced from `colors-rgb` lines 1
(background, used 3x) and 2 (accent, used 2x) — the rest of the theme's
colors are static, hand-authored CSS, not pywal-templated. **wallust changes
nothing here as long as `colors-rgb` is regenerated with the same line
order** (§4/§5). No Discord-specific work required beyond that.

## 3. Spotify (via Spicetify)

Two-hop chain: `pywal-spicetify` (compiled Go binary, confirmed via
`strings`) reads its own rendered template at `~/.cache/wal/
colors-spicetify.ini`, which itself came from the **untracked, local-only**
`~/.config/wal/templates/colors-spicetify.ini` (§0) via pywal's/pywal16's
user-template mechanism, and writes the result through the symlink at
`~/.config/spicetify/Themes/wal/color.ini` back into this repo's
`configs/spotify/color.ini`. wallust can reproduce this exactly: register
that same template file (after copying it into the repo, §0) as a wallust
`[templates]` entry with `pywal = true`, target
`~/.cache/wal/colors-spicetify.ini` — byte-identical output, `pywal-spicetify`
never needs to know wallust generated it.

## 4. Firefox — pywalfox

**Already installed and wired**, not a gap to invent: `install.sh:334`
(`python-pywalfox`), a registered native-messaging host
(`/usr/lib/mozilla/native-messaging-hosts/pywalfox.json`), and the browser
extension itself present in a real profile
(`~/.config/mozilla/firefox/42l6ldzp.default-release/extensions/
pywalfox@frewacom.org.xpi`).

Read `/usr/lib/python3.14/site-packages/pywalfox/config.py` and
`fetcher.py` directly:

- It **hardcodes** `PYWAL_COLORS_PATH = $XDG_CACHE_HOME/wal/colors.json`
  and reads exactly two keys: `colors` (needs ≥16 entries) and `wallpaper`.
  No pywal binary is ever invoked by pywalfox itself — it's a pure
  `colors.json` consumer, same as everything in §1. **Zero pywalfox-specific
  work is needed** as long as wallust's `colors.json` template preserves
  that shape.
- **It is currently broken, independent of pywal vs. wallust.**
  `~/.cache/pywalfox.log` shows `ERROR:Could not find profiles.ini in
  Firefox profiles folder` on every run going back weeks. Root cause, found
  by reading `config.py`: pywalfox only looks in
  `~/.mozilla/firefox` or `$XDG_CONFIG_HOME/firefox`
  (i.e. `~/.config/firefox`) for `profiles.ini` — but this repo's actual
  profile lives at `~/.config/mozilla/firefox/` (confirmed: `profiles.ini`
  is really there), a third location pywalfox's own code doesn't check.
  **Pre-existing defect, unrelated to this migration** — likely fixable
  with `ln -sf ~/.config/mozilla/firefox ~/.config/firefox` so pywalfox's
  XDG lookup finds it, but that's a separate fix and out of scope here;
  flagging it because "fully supports Firefox" should not silently inherit
  a defect that predates this plan.

No other browser in this repo is themed from pywal — `qutebrowser` is
installed (`install.sh:340`) but nothing under `configs/qutebrowser/`
references wal/pywal at all, and there is no `configs/firefox/` directory
(Firefox has no *repo-tracked* config here beyond the extension install —
its theming lives entirely in the pywalfox daemon + colors.json).

## 5. wallust capabilities (from `wallust.toml`'s shipped sample config,
`schema.json`, and the README, all read directly from
`codeberg.org/explosion-mental/wallust`)

- **Backends** (`backend =`): `fastresize` (SIMD resize, default,
  recommended), `resized` (standard resize), `full` (every pixel, slowest,
  most precise), `thumb` (fixed 512×512 crop, fastest), `wal` (shells out to
  ImageMagick `convert`, i.e. literally pywal's own method, for an
  apples-to-apples comparison run — see §6).
- **Palette modes** (`palette =`): `salience` (perceptually prominent
  colors, default, has `sampling`/`intensity` sub-options), `ansi`
  (classic fixed TTY layout: color1=red, color2=green, ...), `kmeans`
  (Lab-space clustering, has `k`/`min_dist` sub-options).
- **Templates**: two syntaxes — a Jinja2 subset (default,
  `{{background}}`, filters like `{{foreground | blend("#eee")}}`) or
  **pywal syntax** (`{color2}`, `.strip` etc.) enabled per-template with
  `pywal = true`. Templates live under `~/.config/wallust/`, mapped in
  `wallust.toml`'s `[templates]` table: `name = { template = 'relative/src',
  target = '/absolute/dest', pywal = true|false }`. **The sample config
  ships an explicit pywal-compatibility example**: `wal = { template =
  'wal/', target = '~/.cache/wal/', pywal = true }` — i.e. wallust natively
  supports regenerating an entire directory of pywal-syntax template files
  into `~/.cache/wal/` in one shot. This is the mechanism §6's Track A
  plan uses.
- **Hooks**: `[hooks]` runs a plain shell command after generation (`--
  no-hooks` to skip); `[templated_hooks]` does the same but the command
  string is itself rendered as a Jinja2 template first, with the same
  variables templates get (`colors`, `wallpaper`, `palette`, ...). This can
  replace some of `switch-wallpaper.sh`'s post-`wal` `sed` calls with real
  templating later (§6 Track B), though nothing requires that for
  correctness now.
- **No built-in templates ship with wallust itself** (unlike pywal16's 56).
  You supply every template file. This is not a functional gap — pywal16's
  own template files are plain text on this machine right now
  (`/usr/lib/python3.14/site-packages/pywal/templates/*`) and can be copied
  wholesale into `~/.config/wallust/templates/wal/`, then rendered with
  `pywal = true`. Confirm each copied file's syntax is plain `{color0}` /
  `{background.strip}` style (it is, per the pywal User-Template-Files
  syntax wallust explicitly targets for compatibility) before relying on
  it — a handful of pywal16's newer templates may use pywal-specific
  syntax additions wallust's compat mode doesn't cover; spot-check the
  ones this repo actually uses (`colors`, `colors.json`, `colors-rgb`,
  `colors.sh`, `colors-kitty.conf`, `colors-oomox`, `ghostty.conf`) during
  Phase 1 rather than assuming all 56 port cleanly — only those 7 matter to
  this repo.

## 6. Migration strategy — two tracks

**Track A — swap the engine, keep every output byte-identical.** Copy
pywal16's template files for the 7 templates this repo actually reads
(listed above) into `~/.config/wallust/templates/wal/`, register them as a
single `wal = { template = 'wal/', target = '~/.cache/wal/', pywal = true }`
entry (plus the Spotify template from §0/§3 as a second entry targeting
`colors-spicetify.ini`), and change exactly one line in
`scripts/switch-wallpaper.sh`: `wal -i "$file"` → `wallust run "$file"`.
Every file in §1's inventory keeps reading the same paths in the same
format; nothing downstream changes. This is the low-risk, complete option —
it satisfies "fully replace pywal" (the `wal` binary is gone, `wallust` does
100% of the color extraction) without touching Discord, Firefox, Spotify,
KDE, GTK, kitty, ghostty, zsh, bmenu, walker, hyprlock, Zed, or VSCodium
integration code at all.

**Track B — modernize templates to native Jinja2, one at a time, optional
follow-up.** Once Track A is stable, individual templates can be rewritten
in wallust's native syntax for readability/filters (e.g. `{{background |
lighten(0.1)}}` instead of manual `.strip` chains), and some of
`switch-wallpaper.sh`'s `sed`-into-line-position hacks (hyprlock, walker,
Discord CSS) could become real templates or `[templated_hooks]` entries
instead of positional line extraction from `colors-rgb`. This is strictly
an internal-quality improvement — do it lazily, per-file, never as a single
big-bang rewrite, and diff rendered output against Track A's before
switching each one over.

## 7. Phased plan

Effort labels as in `ROADMAP.md`: **S** ≈ under an hour, **M** ≈ a few
hours, **L** ≈ a day or more.

1. **(S) Back up the untracked spicetify template.** Copy
   `~/.config/wal/templates/colors-spicetify.ini` into the repo (§0) before
   doing anything else — it is invisible to every grep of this repo and
   will not survive a fresh machine setup otherwise.
2. **(S) Install wallust**, `wallust cs`/`wallust run` smoke-tested against
   one wallpaper with `backend = "wal"` (ImageMagick, same extraction pywal
   used) to get an apples-to-apples palette before introducing any
   algorithm change.
3. **(M) Build the Track A template set.** Copy the 7 relevant pywal16
   templates + the Spotify template into `~/.config/wallust/templates/`,
   write `wallust.toml`'s `[templates]` block, run `wallust run` by hand,
   diff every generated file in `~/.cache/wal/` byte-for-byte against what
   `wal -i` produces for the same image.
4. **(S) Flip the trigger.** One-line change in
   `scripts/switch-wallpaper.sh`. Run the full wallpaper-switch flow for
   real, verify Hyprland borders, kitty, ghostty, walker, hyprlock, Zed,
   VSCodium, herdr, KDE/Qt, GTK, Discord, Spotify, and the Quickshell bar
   all pick up the new palette.
5. **(S) Switch `backend` to `fastresize`/`salience`** (wallust's
   recommended defaults) only after step 4 is confirmed stable — this is
   the point where palette *values* actually change, see §8.
6. **(S) Update the two doc conflicts.** `ROADMAP.md` Ground rule #3 and
   `00-index.md`'s "Conventions these docs assume" pywal-only line, per
   this doc's opening note.
7. **(Optional, S each) Track B items**, taken individually, never batched.

## 8. Risk & rollback

- **Palette values will visibly shift the moment the backend/palette mode
  changes from ImageMagick `convert`** (what pywal always used) **to
  wallust's own algorithms.** Every themed surface in §1 changes color at
  once, simultaneously, system-wide — there is no partial state. Mitigate
  by doing step 5 (the actual algorithm change) as its own separate,
  observable step after step 4 (the engine swap, byte-identical output) is
  already proven stable — isolates "did the migration break something" from
  "I don't like the new palette" as two independent questions.
- **Rollback is a one-line revert** of `scripts/switch-wallpaper.sh`'s
  trigger line back to `wal -i`, as long as `python-pywal16` stays installed
  during the bake-in period (it will, transitively, unless
  `pywal-spicetify` is also removed — don't remove it during this
  migration).
- **`pywal-spicetify` is a compiled binary whose exact behavior wasn't
  fully inspectable** (Go binary, only `strings`-readable) — verify
  empirically after step 3 that it still successfully renders
  `configs/spotify/color.ini` through wallust-generated
  `colors-spicetify.ini`, rather than assuming from the `strings` output
  alone.

## 9. What, if anything, pywal(16) does that wallust cannot replicate

Nothing found that's a hard blocker for this repo's actual usage. The two
real differences are template *authorship burden* (wallust ships zero
built-in templates vs. pywal16's 56 — addressed by Track A's one-time copy,
§5/§6) and needing to manually verify each copied template's pywal-syntax
compatibility rather than trusting it blindly (§5's closing paragraph). If
Track A's diffing step (Phase 3) turns up a template that doesn't render
identically, that's the place it will surface — not discovered here.
