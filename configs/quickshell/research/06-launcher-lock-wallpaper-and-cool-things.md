# Launcher, Lock, Wallpaper, and Cool Things (2026-09)

Status: DRAFT — companion to `01-ecosystem-survey.md`. Same constraints apply:
pywal-only theming (no multi-theme/Material-You layer), panels open on HOVER not
click (deliberate, do not suggest reverting), persistent state changes go through
`toggles/toggle-*.sh` (never QML writing config files directly), Arch + Hyprland +
single user, font pinned to `"0xProto Nerd Font"`.

Repos read directly (via `gh api`/`gh search code`, not scraped): `basecamp/omarchy`,
`caelestia-dots/shell`, `AvengeMedia/DankMaterialShell`, `end-4/dots-hyprland`.
Noctalia (`noctalia-dev/noctalia-shell`) turned up no code-search hits for the
specific symbols searched (`WlSessionLock`, `launcher`, `ScreencopyView`) — either
its layout uses different names or its default branch wasn't indexed at query
time; not covered below beyond what general knowledge already contributed to
`01-ecosystem-survey.md`.

Marking convention: **BUILT-IN** = ships in Quickshell itself (`Quickshell.*`
QML types/singletons). **SUBPROCESS** = shells out to an external binary.
**NATIVE PLUGIN** = requires a compiled C++ Quickshell plugin (a real build
step, not just QML) — flagged separately since it's a much bigger investment
than either of the other two.

---

## 1. Wallpaper/theme switching

### How Omarchy actually does it

`omarchy-theme-set` (`bin/omarchy-theme-set`,
https://github.com/basecamp/omarchy/blob/master/bin/omarchy-theme-set) is a
staging-directory + atomic-swap design, not an in-place edit:

- Builds a fresh `~/.local/state/omarchy/current/next-theme` directory (`rm -rf`
  + `mkdir -p`), copies the official theme's files in, then overlays the user's
  own theme directory on top — but only file-for-file: `.lua` files, and
  per-terminal configs (`alacritty.toml`, `foot.ini`, `ghostty.conf`,
  `kitty.conf`, `vscode.json`) from a theme that "came from a repo" (has a
  `.git` dir — i.e. `omarchy theme install`) are explicitly *denied* from being
  staged (`INSTALLED_THEME_DENIED` array) because they're either executable
  code Hyprland/Neovim load at startup, or name a program/extension the shell
  would then launch on the user's behalf. A theme the user wrote by hand is
  trusted with everything. This is a real security boundary, not incidental.
- The whole staging+swap is `flock`-serialized (`$THEME_SET_LOCK`) so two
  concurrent theme changes can't interleave and silently drop one.
- Colour generation is **push, not poll**: once `colors.toml`/`shell.toml` exist
  in the new theme dir, they're base64-encoded and handed directly to a running
  Quickshell instance via `omarchy-shell -q shell applyTheme <colorsB64>
  <shellB64>` (an `IpcHandler{ target: "shell" }` in
  `shell/shell.qml`, https://github.com/basecamp/omarchy/blob/master/shell/shell.qml#L879
  — `Color.loadColors(...)`, `Color.loadShell(...)`, `Style.scheduleRefresh()`).
  There is no file the shell watches for the *theme* itself; the palette
  arrives as an IPC call synchronously with the rest of the theme swap.
- Background swap goes through the same IPC channel with an actual crossfade
  payload: `set_theme_background()` snapshots the *old* background file (hard
  link, falls back to copy) and the *new* one into
  `~/.cache/omarchy/background-transitions/`, then calls
  `omarchy-shell background themeTransition <oldSnapshot> <newSnapshot>
  <finalPath> <colorsB64> <shellB64>` — the shell gets both endpoints of the
  crossfade in one call and animates between them
  (`shell/plugins/background/Background.qml`,
  https://github.com/basecamp/omarchy/blob/master/shell/plugins/background/Background.qml#L150,
  `function themeTransition(...)`). If the IPC call fails (shell not running),
  it falls back to `shell_ipc shell applyTheme ... || true` — theme still
  applies, just no live animation.
- After the swap, `run_parallel` fires ~14 independent per-app retint/restart
  hooks (`omarchy-restart-terminal`, `-btop`, `-opencode`, `-helix`,
  `omarchy-theme-set-foot/-tmux/-gnome/-pi/-claude/-browser/-vscode/-obsidian/-keyboard`)
  — this is the direct analogue of this repo's `scripts/switch-wallpaper.sh`
  doing the same job with `sed -i` + background `&` jobs for hyprlock, walker,
  zed/vscodium, Discord, GTK, pywalfox, pywal-spicetify, nvim, waybar, ghostty.
  Same shape, different mechanism (Omarchy has per-app *templates* rendered
  from `colors.toml`; this repo has per-app `sed` patches applied to whatever
  the app's live config already contains).
- `omarchy-theme-bg-next` (https://github.com/basecamp/omarchy/blob/master/bin/omarchy-theme-bg-next)
  cycles backgrounds *within* the current theme (reads
  `~/.local/state/omarchy/current/theme/backgrounds/` + a user override dir,
  finds the current one via the `background` symlink, wraps to the next) —
  colours do **not** change on a background-only cycle, only on
  `omarchy-theme-set`. That decoupling (theme palette vs. which of N stock
  backgrounds is showing) has no equivalent need here, because in a pywal-only
  world the background *is* the colour source — cycling background always
  means recomputing the palette.

### Contrast with this repo's pywal flow

This repo's `scripts/switch-wallpaper.sh` (`configs/quickshell` sibling,
`scripts/switch-wallpaper.sh`) is architecturally simpler because it has to
be: `wal -i "$file"` *derives* the palette from the image, so there is no
separate "theme" object to stage — image and palette are the same generation
event, always in that order (pick image → `wal` → recolor everything). The
push/poll split is inverted from Omarchy too: `Commons/Color.qml` watches
`~/.cache/wal/colors.json` itself (`FileView`/`watchChanges`, per
`l-quickshell`'s own orientation notes) rather than the shell being told via
IPC — closer to Omarchy's *fallback* path (`shell_ipc ... || true`) being the
*only* path here, permanently. That's fine for a single-user, single-theme-
source setup; it just means recolor latency is bounded by however fast the
file watcher notices the write, not by a synchronous IPC call. Given this is
already working (`plugins/notifications/` recolors live off it per the
script's own comment), there's no strong reason to add an IPC push purely
for colours — but the *background* transition (below) is a different story.

### A native wallpaper-switcher panel — most of it already exists

`configs/quickshell/plugins/image-picker/ImagePicker.qml` (603 lines) +
`ImagePickerModel.js` + `list.sh` is a **complete, unwired** thumbnail
picker: `list.sh` maintains a content-hash-cached JPEG thumbnail index
(`~/.cache/quickshell/image-selector/index.tsv`, keyed by `stat -Lc '%s:%Y'`
signature so edits/replacements auto-invalidate, `find -L` so symlinked
wallpaper dirs work), and `ImagePicker.qml` has keyboard nav
(`selectAdjacent`), text filtering (`updateFilter`), and an IPC `open()`
matching Omarchy's own image-selector contract (`imageDirs`,
`selectionFile`, `doneFile`). Its `manifest.json` literally describes it as
"used for wallpapers, themes, and any other directory of images" and sets
`"keepLoaded": true`. Wiring it as the wallpaper switcher means:

- Point `openSelector()` in `plugins/background/Background.qml`
  (currently `Util.execDetached(... switch-wallpaper.sh)`, i.e. it shells
  out to the *terminal* fzf/chafa picker on double-click) at this panel
  instead, passing `WALLPAPER_DIR` as `imageDirs` and having its
  `doneFile`/selection callback invoke `scripts/switch-wallpaper.sh
  <chosen-path>` via `Process` — keeps the actual palette-generation and
  40-ish app-retint steps in the shell script (correct: that's exactly the
  kind of persistent/system-wide side effect that should never move into
  QML per this repo's toggle-script convention), QML only picks the file.
- **Shuffle**: `switch-wallpaper.sh random` already exists (`shuf -n1`) —
  one button that calls the same script with `random`, no new logic.
- **Per-monitor assignment**: real constraint, not just an implementation
  gap — pywal is one global palette generated from one image. Assigning
  different wallpapers to `eDP-1` vs `DP-1`/`DP-2` (this repo's actual
  3-output rig, `configs/hyprland/hyprland_monitors.lua`) is easy at the
  *paint* layer (`Background.qml`'s `Variants { model: Quickshell.screens }`
  already renders each screen independently and could read a per-output
  symlink), but the *palette* would still have to pick one winner image to
  feed `wal -i`. Recommend: keep it simple — one wallpaper drives colours
  for everyone, but let the picker optionally set a per-output override for
  the *paint* only (a decorative background), clearly separated in the UI
  from "set as theme wallpaper" (drives `wal`). Don't build the
  Omarchy-style per-theme background carousel; there's no multi-theme layer
  for it to belong to here.
- **Transition animation**: already better than swww/awww's own. Read
  `Background.qml` closely — it doesn't do a plain opacity crossfade, it
  renders a `Shape`-based slanted wipe mask (`revealMask`, `ShapePath`,
  `slant: -0.18`) driven through a `MultiEffect{ maskEnabled: true }`, animated
  over 420ms with `Easing.InOutCubic`, per-screen (`Variants` over
  `Quickshell.screens`), with `Component.onCompleted: refreshBackground()`
  and a `readlink -f` poll of the wallpaper symlink. This is already a more
  interesting effect than `awww img --transition-type center`. Nothing to
  add here design-wise; the panel above is the missing piece, not the
  renderer.

### swww/awww vs hyprpaper vs Quickshell drawing it itself

The task brief says "swww is installed here" — actually check:
`configs/hyprland/hyprland_autostart.lua` execs `awww-daemon`, and
`install.sh` lists the `awww` package (`awww # [desktop] wayland wallpaper
daemon`). `pacman -Si awww` confirms it `Provides: swww` — it's the
actively-maintained fork (upstream `swww` stalled; `awww`,
https://codeberg.org/LGFae/awww, is a drop-in CLI-compatible successor), so
every "swww" fact below applies to the `awww` binary actually running here.

| | SUBPROCESS: awww/swww daemon | SUBPROCESS: hyprpaper | Quickshell paints it (BUILT-IN) |
|---|---|---|---|
| Transitions | Its own GPU shader transitions (`--transition-type`), opaque to Quickshell, compositor-level | None — dumb static painter, IPC-set only | Whatever QML/`MultiEffect`/`Shape` you write — already the nicest of the three here |
| Per-monitor | Native — paints each output independently by default | Native, one `preload`+`wallpaper` line per output | Native via `Variants{model:Quickshell.screens}` — already done in `Background.qml` |
| Survives a Quickshell crash | Yes — separate daemon, image stays up | Yes | **No** — the `WlrLayer.Background` surface goes away with the process; screen falls through to whatever's under it (black, or awww's own layer if still running) |
| Cost when *also* running Quickshell's own painter | Wasted GPU work underneath an opaque QML layer, and undefined z-order between two same-layer (`WlrLayer.Background`) surfaces from different clients — a real flicker/z-fight risk, not just inefficiency | N/A (not installed) | — |

**This repo currently runs both simultaneously** —
`scripts/switch-wallpaper.sh` calls `awww img "$file" --transition-type
center ...` *and* separately updates the `~/.cache/wal/wallpaper` symlink
that `Background.qml` polls and crossfades from. Since `Background.qml`'s
effect is strictly nicer and already per-monitor-correct, the awww call is
redundant work at best and a z-order gamble at worst. Two reasonable fixes,
pick one:

1. **Drop the `awww img ...` line** from `switch-wallpaper.sh` entirely, but
   keep `awww-daemon` autostarting and keep it *pointed at the same
   wallpaper* (a single `awww img "$file"` with no fancy transition, just
   so there's a wallpaper under the layer at all) purely as the
   crash-fallback painter — Quickshell's crossfade is what's visible in the
   normal case, awww is what's visible for the one frame right after a
   Quickshell crash/restart before it reattaches.
2. Or go the other way: kill `awww-daemon` entirely (uninstall or just stop
   autostarting it) and accept that a Quickshell crash means a black screen
   until it restarts — simpler, but loses the crash-fallback property.

Given this repo already treats "don't strand the user" as a first-class
concern (see the lock screen section below), (1) is the better default:
cheap insurance, and it costs nothing since awww is already installed and
autostarted. `hyprpaper` genuinely adds nothing over this — it's strictly
less capable than awww and isn't installed; no reason to introduce it.

---

## 2. App launcher: state of the art

### What's BUILT-IN and already used correctly here

`Quickshell.DesktopEntries.applications.values` (BUILT-IN) is the standard
across every repo surveyed — caelestia's `Apps.qml`
(https://github.com/caelestia-dots/shell/blob/main/modules/launcher/services/Apps.qml,
`entries: DesktopEntries.applications.values.filter(...)`), DankMaterialShell's
`AppSearchService.qml` (`applications = DesktopEntries.applications.values`),
and this repo's own `configs/quickshell/services/AppLibrary.qml`. Nobody
hand-parses `.desktop` files anymore — the built-in type already handles
`Exec` field expansion, `NoDisplay`/`Hidden`, and locale-aware `Name`/
`GenericName`. Icon lookup is also already state-of-the-art here:
`AppLibrary.qml` uses `Quickshell.iconPath(value, true)` (BUILT-IN) *and*
layers a SUBPROCESS icon-index scan (`find` across XDG icon dirs +
`/usr/share/pixmaps`, `configs/quickshell/services/AppLibrary.qml:139`
`iconIndexScanCommand()`) as a fallback for icons installed after Qt's own
icon-theme cache was built — this is a real gap the other repos surveyed
don't obviously cover, worth being proud of rather than replacing.

### Fuzzy matching: three tiers, pick the middle one

- **NATIVE PLUGIN tier** — caelestia's `Apps.qml` extends a `Searcher` base
  component with `keys`/`weights` arrays and backs it with `AppDb`, a SQLite
  store (`Caelestia.Models`, a compiled Qt/C++ plugin) that persists
  `incrementFrequency(entry.id)` across restarts. Real fuzzy scoring +
  durable frecency, but it's a build step (CMake, a real C++ plugin) — not
  a drop-in for a pure-QML repo.
- **BUILT-IN JS tier (recommended)** — DankMaterialShell's `Scorer.js`
  (https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/Modals/DankLauncherV2/Scorer.js)
  is a `.pragma library` — pure JS, no native deps, drop-in replaceable for
  this repo's `services/AppSearch.js`. It layers: exact match (10000) >
  prefix (5000) > word-boundary (3000, tokenizes on `[\s\-_]+` so
  "vs code" matches "Visual Studio Code") > substring (500) > a real
  Levenshtein fuzzy fallback (`levenshteinDistance`, gated to `query.length
  >= 3`, max edit distance scaled by query length: 1/2/3) — plus a
  `frecencyBonus` (capped at 2000) added on top of the text score, and a
  `typeBonus` table (app > plugin > setting > clipboard > file > action) for
  when the launcher is a unified command palette across result kinds, not
  just apps.
- **What this repo has today** — `configs/quickshell/services/AppSearch.js`
  is substring + acronym matching (`entryAcronym` builds first-letters from
  camelCase/`.`/`_`/`-`/`/`-split words, matched only for queries
  `<= 5` chars) with a hand-rolled `fuzzyScore`, but **no real edit-distance
  fuzzy matching and no frecency** — a query with one typo or transposition
  currently just misses. Porting `Scorer.js`'s Levenshtein fallback in
  (keep the existing acronym trick, it's a nice touch DMS doesn't have) is
  the single highest-value, lowest-risk launcher upgrade available: pure
  JS, no new imports, no native build.

### Frecency

DankMaterialShell's `calculateFrecency` (`AppSearchService.qml:584`) is
time-bucket-weighted usage count × a context bonus × `min(usageCount, 10)`
— recently-and-often-used apps rank far above once-used-long-ago ones,
without needing a real database: a small JSON blob in `~/.cache` (not
`~/.config` — this is cache, not repo-tracked config, so it doesn't cross
the "QML never writes config files" line the same way a `toggles/*.sh`
write would) mapping `app.id → {count, lastUsed}`, read at launcher-open and
written via a `Process` on `launchAt()`, is enough. Skip caelestia's SQLite;
a JSON file the launcher already fully owns and rewrites is simpler and this
repo has no other consumer that would need SQL query semantics.

### Calculator / unit conversion / web search / prefix syntax

None of these exist here yet; all are cheap wins. caelestia's prefix scheme
(`>i` id, `>c` category, `>d` description, `>e` exec string, `>w` window
class, `>g` genericName, `>k` keywords, `>t` terminal-only, `>calc `
calculator — `GlobalConfig.launcher.specialPrefix` + `actionPrefix`,
`modules/launcher/services/Apps.qml`) is a clean, discoverable convention
worth copying (some fixed leading character, `search.startsWith(prefix + "c
")` style dispatch) even without its NATIVE-PLUGIN-backed `Qalculator`
binding behind `>calc`. For this repo, calculator mode is a SUBPROCESS one-
liner: `Process{ command: ["qalc", "-t", expr] }` (or `bc -l` if
`qalc`/libqalculate isn't already a dependency worth adding) with a
`StdioCollector`, same shape as `Background.qml`'s existing `readlinkProc` —
no native binding needed for a good-enough result. Web search mode is even
cheaper: a `?` or `g:` prefix that, on Enter, does
`Quickshell.execDetached(["xdg-open", "https://..." + encodeURIComponent(rest)])`.

### Instant appearance

`plugins/image-picker/manifest.json` already sets `"keepLoaded": true` —
the pattern (never destroy the panel, only show/hide) is already this
repo's convention via the hover-panel architecture noted in `l-quickshell`.
`AppSearch.qml`'s `open()` calls `appLibrary.refreshIcons()` +
`rebuildEntries()` synchronously on every open, which is a full app-list
rescan on the critical path to first paint. DankMaterialShell keeps its
launcher's result list warm continuously and only re-scores on keystroke;
the cheap equivalent here is refreshing `AppLibrary`'s icon index on a timer
or after a wallpaper/theme change (already has an `iconIndexDebounce`
timer) rather than unconditionally in `open()` — the list itself barely
changes session-to-session, only icons newly discoverable after installs do.

---

## 3. Lock screen: state of the art

### `WlSessionLock` correctness — the one fact that matters most

Quickshell's docs (https://quickshell.org/docs/v0.2.1/types/Quickshell.Wayland/WlSessionLock/)
confirm: a **single** declared `WlSessionLockSurface` is automatically
instantiated once per connected screen by `WlSessionLock` itself — no
`Variants`/`Repeater` needed. Both this repo's `plugins/lock/Lock.qml`
(one `WlSessionLockSurface` at line 134, direct child of `WlSessionLock`)
and caelestia's `modules/lock/Lock.qml` +
`modules/lock/LockSurface.qml` (https://github.com/caelestia-dots/shell/blob/main/modules/lock/Lock.qml)
use exactly this single-declaration shape and both correctly get
multi-monitor lock surfaces for free. This is *unlike* `Background.qml`,
`Osd.qml`, etc., which need explicit `Variants{model:Quickshell.screens}`
because `PanelWindow` has no such built-in per-screen magic — worth knowing
so nobody "fixes" `Lock.qml` by wrapping it in `Variants` it doesn't need.

**The real risk, and it's a compositor-level fact, not a QML one:** the
Wayland session-lock protocol is deliberately designed so the compositor
stays locked even if the client that requested the lock dies — that's the
entire security point of the protocol (otherwise crashing the locker would
bypass it). On Hyprland, that means a QML exception that kills the
Quickshell process while `sessionLock.locked` is `true` can leave the user
on a frozen/black screen with no way back short of a hard power-cycle,
**unless** `misc:allow_session_lock_restore` is set in the Hyprland config
— confirmed via search of real user reports (recovery procedure: switch to
a TTY, kill the crashed shell, `hyprctl --instance 0 keyword
misc:allow_session_lock_restore 1` then `hyprctl dispatch exec hyprlock` to
get an *unthemed* hyprlock able to actually unlock the session). **This
repo does not currently set that option anywhere in `configs/hyprland/`**
(`grep -rn "allow_session_lock_restore" configs/hyprland/` returns nothing).
Setting it *before* `Lock.qml` is ever wired as the real `lock_cmd` is the
single highest-leverage safety change available here — it's the difference
between "a QML crash while locked means restart" and "a QML crash while
locked means find another machine to look up how to force a reboot from
a TTY you may not be able to reach if the crash also wedges VT-switching."

TTY VT-switch (Ctrl+Alt+F2, log in with the normal account password via
PAM — a *separate* auth path from the Wayland session lock, so it's not
blocked by it) remains the true last resort regardless of that setting, and
should stay documented as such (already implicitly true for hyprlock too —
nothing here is unique to the QML lock).

### PAM patterns

This repo's `Lock.qml` already has a genuinely good fail-safe: `beginLock()`
refuses to set `lockRequested`/`sessionLock.locked` at all if
`pamConfigured` is false (`FileView` watching `/etc/pam.d/quickshell-lock`,
`onLoadFailed: root.pamConfigured = false`) — it is structurally impossible
for this lock screen to enter the locked state without a valid PAM stack
already present, which closes off an entire class of "locked with no way to
authenticate" bugs before they can happen. Keep this exactly as-is.

caelestia's `modules/lock/Pam.qml`
(https://github.com/caelestia-dots/shell/blob/main/modules/lock/Pam.qml) is
the template for adding a **second** PAM path (`fprintd`, which this repo
already has scaffolding for — `configs/fprintd/link.sh`,
`configs/fprintd/python3-validity-override.conf`) without touching the
existing password path:
- One `ManualPamContext`-shaped component per method (password stays as-is;
  add a sibling for fingerprint), each with its **own** `PamContext`,
  `maxTries` counter, and `canAttempt` gate (`available && enabled &&
  locked && tries < maxTries`), so a fingerprint failure never touches
  `root.failedAttempts` on the password side and vice versa.
- Availability is itself probed via a SUBPROCESS liveness check
  (`fprintd-list $USER` exit code) before ever starting a `PamContext` for
  it — don't attempt fingerprint auth against a device that isn't
  enrolled/present, that's just a guaranteed-fail PAM conversation.
- Typing a password character while a fingerprint attempt is in flight
  aborts the fingerprint context (`if (howdy.active) howdy.abort()` in
  `handleKey`) — the two methods should never race for the terminal PAM
  slot at once.
- PAM `Error` results get a bounded retry-with-backoff (`errorTries < 5`,
  800ms `Timer` before `pam.start()` again) separate from *auth* failures
  (`MaxTries`/`Failed`, which count against the real attempt budget) — a
  transient PAM stack hiccup shouldn't burn a real attempt.

### Failed-attempt handling

Current behaviour: increments `failedAttempts`, shows "Authentication
failed (N)", no ceiling — a determined attacker with physical access gets
unlimited password guesses at whatever rate the PAM stack allows. caelestia
gates on `Pam.MaxTries` and fully disables the input field once reached.
Cheap, high-value addition: after e.g. 5 failures, disable
`passwordInput` and show a countdown ("Try again in 30s") via a `Timer` —
raises the cost of brute-forcing meaningfully with about 15 lines of QML,
no new imports.

### Media/notifications/battery on the lock surface

Deliberately not present today — the file's own header comment says the
security-critical surface is being kept "small enough to actually audit."
That's the right call to keep making for now: every additional live widget
on a *locked* surface is more QML that can throw while the user has no
escape hatch except the TTY/`allow_session_lock_restore` path above. Order
of operations matters here — get `allow_session_lock_restore` set and run
the real manual test (`quickshell ipc -p ~/.config/quickshell call lock
lock`, already flagged as never-yet-done in `TODO.md`) with the *current*
minimal surface first; add media/battery/notifications one at a time after,
each with its own live test, not as one batch landing alongside the first
real activation.

### Idle management: who should own idle → lock → dpms

`configs/hyprland/hypridle.conf` currently owns the whole chain today: 10min
→ dim backlight, 15min → `loginctl lock-session` (which resolves to
`hyprlock` via `lock_cmd = pidof hyprlock || hyprlock`), 20min → DPMS off,
30min → suspend (skipped if an SSH session is active, `w | rg -q ssh`).
DankMaterialShell's `IdleService.qml`
(https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/Services/IdleService.qml)
shows the BUILT-IN alternative: Quickshell's `IdleMonitor` type (wraps the
`ext-idle-notify-v1` protocol) can own this same chain entirely in QML —
and gets, for free, things hypridle can't easily do: battery-aware timeouts
(`isOnBattery ? SettingsData.batteryLockTimeout : SettingsData.acLockTimeout`),
a "fade to lock" warning before the real lock fires, and gating on whether
media is actively playing (`mediaPlaying`) so a movie doesn't get
interrupted by an idle-triggered lock.

**Recommendation: don't move ownership.** hypridle is a small, single-
purpose, battle-tested C binary that keeps running even if Quickshell
crashes — exactly the property that matters most here, and the same logic
that argues for keeping `awww-daemon` as a background-painting fallback in
section 1. Moving idle ownership into Quickshell means a Quickshell crash
silently disables locking *and* DPMS-off *and* auto-suspend all at once —
a much bigger blast radius than losing just the bar, and on a laptop
(`eDP-1` in the monitor config) that's a real battery/screen-burn-in risk,
not just an inconvenience. If the fade-to-lock UX ever becomes worth
having, the safer middle path is: hypridle's own timers stay authoritative
for actually dispatching lock/dpms/suspend (so they survive a Quickshell
crash), and `Lock.qml` only adds a short, *non-authoritative* `IdleMonitor`
purely to drive a cosmetic pre-lock fade a few seconds before hypridle's
real deadline — cosmetic-only, never load-bearing.

### What's lost by dropping hyprlock, and a safe migration procedure

hyprlock (`configs/hyprland/hyprlock.conf`) is not just the current
`lock_cmd` — it already has `auth { fingerprint:enabled = true }` live and
presumably working in production, which is real proven fingerprint-auth
mileage `Lock.qml` doesn't have yet. It's also the documented TTY-recovery
command for the exact crash scenario described above
(`hyprctl dispatch exec hyprlock`) — so it should stay installed
*regardless* of whether Quickshell's lock ever becomes the default,
permanently, not just during a migration window.

Safe procedure, extending what `TODO.md` already has queued:

1. Set `misc:allow_session_lock_restore = true` somewhere in
   `configs/hyprland/` first — before any other step below.
2. With a second, already-authenticated TTY session standing by (Ctrl+Alt+F2,
   logged in, idle) as a safety net, run `quickshell ipc -p
   ~/.config/quickshell call lock lock` and confirm real password entry
   actually unlocks. Test a wrong password too (failure message, retry
   works). Deliberately rename `/etc/pam.d/quickshell-lock` temporarily and
   confirm `beginLock()` correctly refuses to lock rather than half-locking.
3. Only after several real successful unlocks, add fprintd as a second path
   per the caelestia-shaped pattern above, and single-shot test *that* the
   same way (TTY safety net standing by again) before trusting it.
4. Only then flip `hypridle.conf`'s `lock_cmd` from `hyprlock` to the
   quickshell IPC call — and keep hyprlock installed and its config intact
   as the documented recovery path, forever, not just until the migration
   feels stable.

---

## 4. Multi-monitor as a first-class concern

This repo's rig is a real, non-hypothetical mixed setup —
`configs/hyprland/hyprland_monitors.lua`: `eDP-1` (laptop, 1920x1080, scale
1) plus `DP-1`/`DP-2` (desktop, two 3840x2160@144 outputs at scale
1.666667) — genuinely different DPI and refresh rate per output, not a
matched pair. Multi-monitor bugs here are not edge cases.

### The pattern already in use, and where

`Quickshell.screens` + `Variants` is already the load-bearing multi-monitor
primitive in five places: `shell.qml` (wraps `Bar` — confirmed by its own
comment, "One Bar per connected screen, matching Quickshell's standard
per-monitor panel pattern"), `Ui/KeyboardPanel.qml`,
`plugins/background/Background.qml`, `plugins/osd/Osd.qml`, and
`plugins/notifications/Service.qml`. It's reactive by design: per official
docs and DeepWiki's write-up of the Quickshell internals
(https://deepwiki.com/quickshell-mirror/quickshell/4.5-platform-specific-window-implementations),
`Variants` over `Quickshell.screens` creates and destroys delegate instances
automatically as outputs connect/disconnect — no manual hotplug handling
needed for anything using this pattern correctly. `WlSessionLock` is the one
exception that needs *no* `Variants` at all (section 3) — don't add it there.

### Known hot-plug pitfalls (from real issue reports, not speculation)

- **Dangling `ShellMonitor` references.** When a screen disconnects, any
  copy of its screen object held elsewhere goes dangling and its properties
  silently return default values (per Quickshell's own `ShellScreen` docs,
  https://quickshell.org/docs/v0.2.1/types/Quickshell/ShellScreen/). Anything
  that caches "the current/primary monitor" as an object reference rather
  than re-deriving it from `Quickshell.screens` on each use will misbehave
  quietly, not crash — the more dangerous failure mode since it won't show
  up as an obvious error.
- **Lock + monitor-disconnect interaction has a real crash history**
  (quickshell-mirror/quickshell#503, "Lockscreen + Turning off Monitor =
  lockscreen crash"). Directly relevant to section 3's migration test plan
  above: the manual unlock test there should include unplugging/replugging
  a monitor *while locked*, not just testing steady-state with all three
  outputs present.
- **Multi-monitor window-close crash reported against caelestia**
  (caelestia-dots/shell#471, "Quickshell crashes when killing a window in
  multi-monitor setup") — evidence this general area is fragile
  ecosystem-wide, not a this-repo-specific risk; budget real testing time
  for any new per-monitor surface accordingly, don't assume "it uses the
  standard `Variants` pattern" alone makes it safe.

### Which surfaces should be per-monitor vs focused-only

Bar, wallpaper (`Background`), and notifications are correctly per-monitor
today (each needs to render *something* on every physical screen the user
can be looking at). Lock is correctly per-monitor via its own built-in
mechanism. Launcher (`AppSearch`) and clipboard are correctly **not**
`Variants`-wrapped — a single command palette should appear once, wherever
the user's attention already is, not spawn a copy on every screen.

**OSD is the one surface that's currently wrong.** `plugins/osd/Osd.qml`
*does* use `Variants{model:Quickshell.screens}` (line 108) — meaning a
volume/brightness change today pops the OSD on *all three* monitors
simultaneously, not just the one the user is actually looking at. That's
pure visual noise on a 3-monitor rig and directly contradicts the "OSD
should be focused-monitor-only" guidance this task itself calls out.
`Quickshell.Hyprland` is already imported elsewhere in this repo
(`plugins/bar/widgets/Workspaces.qml`, `plugins/bar/widgets/KeyboardLayout.qml`,
`Ui/PopupCard.qml`) but not yet used for focused-monitor lookup anywhere.
Fix: replace `Osd.qml`'s `Variants` with a single `PanelWindow` whose
`screen` property is bound reactively to the currently-focused Hyprland
output (via `Quickshell.Hyprland`'s monitor/workspace data, the same
service already powering `Workspaces.qml`) — one OSD instance, always on
the right screen, no `Variants` needed since there's exactly one at a time.

### Scale/DPI

The laptop runs at Hyprland scale `1`, the desktop outputs at `1.666667` —
`hyprland_monitors.lua` already special-cases XWayland scaling for this
(`QT_AUTO_SCREEN_SCALE_FACTOR`/`GDK_SCALE` set per `platform.laptop`,
`xwayland.force_zero_scaling = true`). Quickshell/QtQuick itself is a native
Wayland client and scales its own surfaces per-output automatically, so
nothing here needs replicating — the XWayland dance in that file exists
*because* X11 apps don't get that for free, not because Quickshell needs
help. Worth confirming (not verified in this pass) that any hand-picked
pixel sizes in `Commons/Style.qml` read acceptably at both `1` and
`1.666667` — a size token tuned by eye on one output can look
subtly-off-but-not-broken on the other, which is easy to miss without
actually looking at both screens side by side.

---

## 5. "Are there any other REALLY cool things?"

Ranked, opinionated. "Impact" weighs both visual wow-factor (the aesthetic
target is explicitly "techy, modern, sleek — we want to impress") and how
much it fills an actual gap in daily use, not just novelty.

| # | Idea | What it does | Quickshell API needed | Difficulty | Impact |
|---|---|---|---|---|---|
| 1 | Alt-tab with **live** window thumbnails | Replace static app-icon alt-tab with real-time screen-content previews per window | `ScreencopyView` (BUILT-IN) + `Quickshell.Hyprland` window list | Medium | Very high |
| 2 | Workspace overview/exposé | Zoomed-out grid of all workspaces with live thumbnails, click/drag to switch | `ScreencopyView` + Hyprland IPC workspace layout | High | Very high |
| 3 | Screenshot region-select + annotate | Native region picker (replace `slurp`) with arrow/box/text/blur annotation before copy/save | `ScreencopyView`, `MouseArea`, `Canvas`/`Shape` | Medium | High |
| 4 | Colour picker / eyedropper | Native pixel-sample-under-cursor, hex to clipboard, live preview swatch | `ScreencopyView` (read pixel), BUILT-IN | Low–Medium | Medium-High |
| 5 | Night-light control (already installed, unwired) | Bar toggle + schedule for `hyprsunset` warmth, currently only bound to raw brightness-key gamma nudges | SUBPROCESS (`hyprctl hyprsunset ...`) + `toggles/toggle-nightlight.sh` | Low | Medium-High |
| 6 | Dock with running-app indicators | Persistent app dock, live running/focused dot per app, click to focus/launch | `Quickshell.Hyprland` client list, `DesktopEntries` | Medium | High |
| 7 | OCR-from-screen | Region-select → text → clipboard, using the existing PAM-free auth-less path | SUBPROCESS (`grim`+`slurp`/`ScreencopyView`+`tesseract`) | Low–Medium | Medium |
| 8 | Focus-mode scene | One toggle flips DND, night-light, cyberpunk-shader off, bar auto-hide, notification mute at once | `toggles/toggle-*.sh` composition, BUILT-IN state | Low | Medium-High |
| 9 | Bar auto-hide with reveal-on-hover | Bar slides away when a window is fullscreen/focused near the edge, reappears on hover | `Quickshell.Hyprland` window state, existing `HoverPanel` grace-timer pattern | Low–Medium | Medium |
| 10 | Bluetooth device battery in bar/quick-settings | Per-device battery % for connected BT peripherals (headset, mouse) | BUILT-IN `Quickshell.Bluetooth`/DBus, or SUBPROCESS `bluetoothctl` | Low | Medium |
| 11 | Animated pywal palette transition | Bar/panel colours *tween* to the new palette over ~300ms instead of snapping, on every wallpaper change | BUILT-IN `Behavior on color` in `Commons/Color.qml` consumers | Low | Medium (cheap, very visible) |
| 12 | GPU shader panel backdrops ("liquid glass"/blobs) | Animated shader background behind panels, not just the compositor-wide CRT toggle that exists today | BUILT-IN `ShaderEffect` + `.frag`/qsb, or NATIVE PLUGIN for anything stateful/complex | Medium–High | High (very "techy/sleek") |
| 13 | Unified control centre | One panel: network/bluetooth/audio/power/DND/night-light/focus-mode in one grid instead of scattered bar widgets | Composition of existing services, no new API | Medium | Medium-High |
| 14 | Per-app notification rules | Mute/priority/DND-bypass per app-id, persisted | BUILT-IN notification service already has app-id; needs a small persisted rules file | Low–Medium | Medium |

### Top picks, detailed

**1–2. Live-thumbnail alt-tab and workspace overview — build these together, they share almost everything.**
end-4/dots-hyprland has both, in the open, with exact file names to study:
`dots/.config/quickshell/ii/modules/ii/overview/Overview.qml` (workspace grid),
`dots/.config/quickshell/ii/modules/waffle/taskView/TaskViewWindow.qml` +
`TaskViewWorkspace.qml` (alt-tab-shaped live task view), and
`modules/waffle/bar/tasks/WindowPreview.qml` (a smaller live-preview building
block reusable in a hover tooltip too, not just full alt-tab). All are built
on `ScreencopyView` — BUILT-IN, wraps `wlr-screencopy` — with
`Quickshell.Hyprland`'s workspace/window model driving layout. caelestia's
`modules/windowinfo/Preview.qml` is a third, smaller reference for exactly the
"one live window thumbnail" primitive without the full grid around it — a
good first milestone before attempting the full overview. Worth flagging:
caelestia's own `modules/lock/Lock.qml` includes a deliberate warm-up
`Loader{ sourceComponent: ScreencopyView{...} }` at startup with the comment
"Force a load of a screencopy so the one in the lock works ... the ICC
backend loads async on first request ... which if the lock is the first
request it fails to capture" — i.e. `ScreencopyView` has a real cold-start
quirk, worth reproducing that warm-up trick rather than rediscovering the bug.
This is the single most "impress people" feature on the list — nothing else
here reads as obviously next-generation the way a live Mission-Control-style
overview does, and Hyprland's own IPC already gives everything needed to lay
workspaces out correctly.

**3. Screenshot region-select + annotate.** end-4/dots-hyprland's keybind
file (`dots/.config/hypr/hyprland/keybinds.lua`) shows a genuinely good
resilience pattern worth copying regardless of whether this feature is
built: **the same key combo is bound twice** — once to
`hl.dsp.global("quickshell:regionScreenshot")` (the native QML overlay) and
once, guarded by `qsIsAlive || pidof slurp ||`, to a raw
`hyprshot`/`grim`+`slurp` SUBPROCESS fallback. If Quickshell isn't running
(crashed, mid-restart), the second binding fires instead — screenshotting
never breaks just because the shell did. This dual-bind-with-liveness-guard
pattern is worth adopting for *any* new global-shortcut-triggered QML
feature added here, not just this one — it's cheap and directly serves the
"don't strand the user" principle this repo already applies to the lock
screen.

**4. Colour picker.** Every repo surveyed just shells out to `hyprpicker -a`
(SUBPROCESS) rather than building a native picker — Hyprland's own tool
already samples pixels and copies `#RRGGBB` to clipboard correctly. Building
a QML-native version (via `ScreencopyView` pixel sampling) buys a live
swatch/magnifier UI but not meaningfully better *function* — reasonable to
just wire `hyprpicker -a` behind a bar button/keybind first (near-zero
effort) and only invest in a native picker if the UI polish specifically
matters later.

**5. Night-light — the fastest win on this list.** `hyprsunset` is already
installed (`install.sh`) and already wired into raw gamma-nudge keybinds
(`configs/hyprland/hyprland_keybindings.lua`: `SHIFT+XF86MonBrightnessUp/Down`
→ `hyprctl hyprsunset gamma ±5`), but there is **no on/off toggle, no
scheduled warm-at-sunset behaviour, and no bar indicator** — it's a raw
keybind with no discoverability. This is exactly the shape of thing
`toggles/toggle-*.sh` already exists for: a `toggles/toggle-nightlight.sh`
(check via `hyprctl hyprsunset temperature`/whatever query it exposes,
`turn_on`/`turn_off` via `hyprctl hyprsunset temperature <K>` or its
toggle subcommand) plus a small bar widget mirroring the existing toggle-menu
widgets, and optionally a sunset/sunrise cron-style scheduler
(`scripts/system-update.sh`-adjacent, or a systemd timer) that calls the
toggle automatically. Low effort, directly visible, and closes a real gap
(the feature exists at the binary level and is completely invisible in the
UI today).

**6. Dock.** `dots/.config/quickshell/ii/modules/ii/dock/DockApps.qml` is the
reference. Combines cleanly with launcher work (section 2) since both need
the same `DesktopEntries` + running-window-by-app-id lookup
(`Quickshell.Hyprland`'s client list, matched by `class`/`initialClass`).
Medium effort mostly because "which apps are pinned vs currently running vs
both" state needs a small persisted list — same JSON-cache pattern
recommended for launcher frecency in section 2, no new infrastructure.

**8. Focus-mode scene.** This repo already has the building block for
"flip several toggles at once" — `toggles/menu.sh` and the individual
`toggle-*.sh` scripts each expose `check`/`turn_on`/`turn_off` with a
consistent interface (`toggles/lib.sh`'s `toggle_main`). A "focus mode"
scene is just a new script in the same family that calls several existing
toggles' `turn_on`/`turn_off` in sequence (DND on, night-light on,
cyberpunk-shader off, bar transparency/auto-hide on) and itself exposes the
same `check`/`turn_on`/`turn_off` shape so it drops into the existing menu
with zero new UI code — genuinely close to free given what's already built,
and a nice showcase of the toggle system's own composability.

**11. Animated palette transition.** The cheapest item on this whole list
with real visible payoff: every colour consumer already reads from
`Commons/Color.qml`; wrapping the properties it exposes in `Behavior on
color { ColorAnimation { duration: 300 } }` (or applying it once at a common
ancestor level if Qt Quick's property-binding propagation allows it) makes
every wallpaper change ripple a smooth colour tween across the whole
desktop instead of an instant snap — directly serves "techy, modern, sleek"
for near-zero implementation cost, since the wallpaper crossfade in
`Background.qml` already takes ~420ms and an un-tweened colour snap
alongside it currently reads as visually mismatched.

**12. GPU shader panel backdrops.** Distinct from the *existing*
`toggles/toggle-cyberpunk-shader.sh`, worth being precise about the
difference: that toggle sets Hyprland's own compositor-wide
`decoration:screen_shader` (a `hyprctl eval` call swapping in
`crt-effect.frag`, affecting literally everything on screen including
windows) — not a Quickshell-local effect at all. A *panel-local* shader
backdrop (animated gradient/blob/noise behind just the bar/panel chrome,
using Qt Quick's `ShaderEffect` with a compiled `.qsb`) is a different,
additive thing — caelestia's `plugin/src/Caelestia/Blobs/shaders/blob.frag`
+ `modules/background/DesktopClock.qml`'s `ShaderEffect` usage is the
reference for an animated-blob aesthetic specifically. Marked
Medium–High because a *good* shader here (not just a gradient) benefits
from being pywal-palette-driven (uniforms fed from `Commons/Color.qml`),
which is straightforward, but genuinely good-looking procedural shader work
takes iteration regardless of the API being simple.
