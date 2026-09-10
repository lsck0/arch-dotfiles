# Ryoku UI/UX & Hyprland patterns — research

Not part of the SPEC gap-closing sequence (docs 00–08 + `ROADMAP.md`). This
is a separate side-investigation: the owner watched a video on **Ryoku**
(`github.com/Gamer1000YT/ryoku-archiso`, docs at `docs.ryoku.dev`), a
Hyprland + Quickshell "Omarchy alternative", liked its visual style, and
asked to record the reusable UI/UX and Hyprland patterns for possible
adaptation. Written 2026-09-02 from a clone of the repo (`docs/` folder and
QML/Lua source read directly, not scraped from the marketing site).

**UPDATE 2026-09-03 — most of this HAS now been applied.** The owner asked
for a full UI overhaul and picked, from the options in §1/§2:

- **Colour: keep pywal fully** — background *and* accent stay
  wallpaper-derived, with Ryoku's conditioning math layered on top. This is
  option (a) from §1's open question: port the *math*, not the backend. The
  `CONFLICTS` note below is therefore resolved in favour of keeping pywal;
  `00-index.md`'s "theming is pywal-only" convention stands unchanged.
- **Geometry: full brutalist** — zero radius, 1px hairlines, hard offset
  shadows. §2 called this "most likely the specific thing that reads as
  distinctive", and that judgement held up.
- **Type: mono only** — §2's Fraunces/Space Grotesk stack was *not* taken.
  Hierarchy comes from weight, size and uppercase wide-tracked headers
  instead, keeping the terminal-native character and requiring no new fonts.

Not applied: the "frame" blob effect (§3, needs a C++ plugin) and the
wallust backend swap (§1 — see `pywal-wallust-migration.md`, deliberately
deferred because Track A is byte-identical by design and so changes nothing
visually). §4's `optional(mod)` guarded Hyprland loader is still open and
still worth doing.

Everything below is Ryoku's approach as originally recorded, kept as written.

---

## 1. Theming pipeline

Ryoku's theming is two singletons per Quickshell surface:

- **`Singletons/Theme.qml`** — a flat token file. Every color, font size,
  radius, and shadow value is a `readonly property`, nothing hardcoded in
  components. Their own stated rule: *"add a token or read one; never write
  a hex, a font name, or a radius literal in a component."*
- **`Singletons/Wallust.qml`** — watches `~/.cache/wallust/colors.json`
  (written by the `wallust` CLI on wallpaper change, templated from
  `ryoku/shell/wallust/wallust.toml`, which also feeds Kitty and a
  Hyprland-lua border-color file) and does real color processing on it:
  - Tone-maps the wallpaper's dominant background color into a fixed dark
    HSV band (value clamped to `[0.08, 0.26]`) so the shell background
    stays legible regardless of wallpaper brightness.
  - "Vivifies" the accent color — floors its brightness/saturation so a
    muted or desaturated wallpaper still yields a punchy accent instead of
    a washed-out one.
  - A `legible()` function implementing real WCAG contrast math: walks the
    accent color toward white in ~18% steps until it clears a 3:1 contrast
    ratio against the surface color, so the accent never becomes
    unreadable text.

Each Quickshell surface (bar, launcher, overview, widgets, welcome,
screenshot tool, visualizer, plugin host, wallpaper picker — each its own
`qs -c <name>` process) carries its **own copy** of these singletons rather
than sharing one instance. Deliberate isolation, not an oversight.

**CONFLICTS with this repo's stated convention:** `00-index.md` records
"theming is pywal-only... there is no multi-theme layer and one should not
be added." Wallust and pywal are not the same tool — wallust does its own
extraction and produces its own JSON schema — so lifting `Wallust.qml`
verbatim would mean swapping the theming backend, not just restyling. **Open
question, not resolved here:** whether to (a) leave pywal as the extraction
backend and just port the tone-mapping/vivify/`legible()` *math* on top of
pywal's existing `colors.json`, or (b) switch backends to wallust outright.
(a) is far less invasive and keeps every other doc's assumption intact —
recommended if this gets picked up, but it's the owner's call.

## 2. Visual style ("Greek-noir", per their `docs/ui-ux.md`)

- **Palette:** near-black canvas (`#100d08` / `#16110b` / `#0f0c07`),
  warm-white text ramp that never touches pure white
  (`#f3ede1` → `#8f8770`), one accent — vermillion `#e2342a` by default,
  swapped for the wallpaper-derived accent when "match wallpaper" is
  enabled — and gold (`#d9a441`) reserved *only* for "kintsugi"
  highlights/warnings, explicitly never used as a second general-purpose
  accent hue.
- **Geometry is brutalist, the opposite of most Hyprland rices:**
  `radius: 0` almost everywhere (only true circles are round), 1px
  hairline borders, and **hard offset shadows instead of blur or glow** — a
  solid black rectangle pushed 6–8px down-right behind each surface, drawn
  with `antialiasing: false` so the edge stays crisp rather than soft. This
  is most likely the specific thing that reads as "distinctive" — it's a
  flat, punchy, high-contrast look rather than the soft/frosted-glass
  aesthetic most Quickshell/Hyprland setups converge on.
- **Type:** Fraunces for headlines, Space Grotesk for UI text, JetBrains
  Mono Nerd Font for labels (set uppercase, wide letter-tracking), Noto
  Sans CJK JP for their 力 (Ryoku) kanji brand mark.
- **Hyprland decoration values** (for reference, not prescriptive):
  `rounding: 2`, `rounding_power: 4`, `border_size: 2`, blur `size: 4,
  passes: 1, vibrancy: 0.17`, shadow `range: 45, render_power: 4`, custom
  bezier animation curves (named `ryokuBloom` / `ryokuSettle`, both with a
  slight overshoot) — all gated behind a `performance.json` low-power flag
  checked via plain string matching (no JSON library dependency pulled in
  just for a boolean read).

**COMPATIBLE:** none of this depends on wallust or their CLI — the color
tokens, zero-radius/hard-shadow geometry, and font choices could be applied
to this repo's existing pywal-driven `Theme`/`Style` singleton(s) as a pure
restyle, independent of the theming-backend question in §1.

## 3. The "frame" — not portable

Their signature effect (`docs/frame.md`): the screen border and every open
popout visually melt into one continuous shape via smooth-min blending — a
metaball/SDF effect. This is implemented as a **compiled C++ Quickshell
plugin** (`Ryoku.Blobs`), not QML. Skip this unless there's appetite for a
native Quickshell plugin build step (this repo's `plugins/` directory is
pure QML today — see `01-ecosystem-survey.md`'s note on native plugins
being "a much bigger investment"). Flagging it so it isn't mistaken for a
CSS-blur-style trick later.

## 4. Hyprland config patterns

Also Lua-authored, same approach as this repo's `configs/hyprland/*.lua`
(loaded via `hl.config()` / `hl.curve()` / `hl.animation()` calls), split
into one file per concern under `ryoku/hyprland/modules/`: `env`,
`keyboard`, `displays`, `input`, `misc`, `decoration`, `animations`,
`binds`, `resize`, `window_rules`, `fullscreen`, `autostart`.

The one structural pattern worth lifting regardless of the theming
question: `hyprland.lua` loads modules through a guarded `optional(mod)`
helper that first probes whether the module file exists, then `pcall`s the
`require`, so a missing or broken drop-in degrades gracefully instead of
putting Hyprland into a config-error state. Load order is explicit and
matters: hardware-generated drop-ins → base modules → machine-written state
→ the user's own `user.lua` loaded **last**, so hand edits always win over
anything generated. This repo's own `configs/hyprland/*.lua` files are
`require`d directly with no such guard today — worth a look independent of
anything else in this doc, since a syntax error in one module currently has
no documented fallback behavior here.

## 5. Plugin architecture note

Third-party Quickshell plugins in Ryoku follow a strict contract
(`docs/plugins.md`): a plugin author supplies only content/logic
(`service/Main.qml`, `content/Widget.qml`); Ryoku itself always owns
positioning, sizing, chrome, and theming, so a plugin can never look
bolted-on or fight the host's visual language. This repo's `plugins/`
directory (bar/background/lock/osd/clipboard/appsearch/etc., per
`00-index.md`) is self-contained per-plugin already, but doesn't enforce
this separation as a contract — each plugin currently owns its own chrome.
Not an immediate gap, just a naming of the pattern in case plugins here
ever need to be pluggable by something other than the repo owner.

---

## Summary: what's actually liftable

| Pattern | Portable? | Depends on |
| --- | --- | --- |
| Flat token-only `Theme.qml` structure | Yes | Nothing — could restructure existing theme singleton(s) this way today |
| Tone-map / vivify / `legible()` contrast math | Yes, as math | A `colors.json`-shaped input — works on pywal's output as-is |
| Palette (near-black canvas, warm-white text, single accent + reserved warning hue) | Yes | Nothing |
| Zero-radius, hairline-border, hard-offset-shadow geometry | Yes | Nothing |
| Font stack (Fraunces / Space Grotesk / JetBrains Mono) | Yes | Font availability only |
| Wallust as theming backend (vs. pywal) | Open question | Would replace this repo's pywal pipeline — explicitly flagged as unresolved in §1 |
| "Frame" blob-merge effect | No, not without a build step | Native C++ Quickshell plugin |
| `optional(mod)` guarded Hyprland module loader | Yes | Nothing — independent of theming decision |
| Plugin content/chrome separation contract | Optional | Only matters if plugins here become third-party-authored |
