# ROADMAP — implementing the quickshell DE spec

The sequenced implementation plan for the SPEC in `prompts.md`. Derived from
`07-spec-conformance.md` (what the gaps are) and docs 01-08 (how to close
them). **This file is the plan; the research docs are the reference.** Where
a step says "see 03 §1", go read it rather than improvising.

Phases are ordered by dependency, not by value. Where a phase has no
dependency, it is ordered by value-to-effort. Effort labels are rough:
**S** ≈ under an hour, **M** ≈ a few hours, **L** ≈ a day or more.

---

## Ground rules (apply to every phase)

1. **`toggles/*.sh` owns every persistent state change.** QML may *read*
   state via native Quickshell bindings; it must *write* through a toggle
   script, so `menu.sh`, keybinds and herdr keep working when the shell is
   not running. Full contract in `02-toggle-contract.md`.
2. **Panels open on hover, not click.** Deliberate; the SPEC says "on hover"
   nine times. Never "fix" this toward click-to-toggle.
3. **Theming is wallust-only**, from `~/.cache/wal/colors.json` (wallust
   replaced pywal 2026-09-03 and writes the same paths — see
   `pywal-wallust-migration.md`). Never hardcode a color or size — pull from
   `Commons/Color.qml` and `Commons/Style.qml`.
4. **Verify every new glyph against `0xProto Nerd Font`'s cmap with
   `fontTools` before shipping it.** Guessed codepoints have silently
   resolved to wrong glyphs more than once (one landed on
   `md-numeric_5_box_multiple`).
5. **`~/.local/state/quickshell/shell.json` is the live bar layout**, and it
   overrides `shell.qml`'s `builtinShellConfig`. Change both, or the change
   does not survive a fresh setup. Read the state file first when auditing.
6. **Launch only via `restart.sh`** (no single-instance guard). It `exec`s
   in the **foreground** — never wrap it in `timeout`, and launch detached
   (`setsid nohup quickshell -p ~/.config/quickshell &`) from scripts.
7. **A panel plugin owning a long-running subprocess must set
   `"keepLoaded": true`** in its manifest, or the Loader destroys the
   `Process` before it can exit cleanly and orphans children.
8. **Commits go through `sync.sh`.** Do not `git commit` by hand here.

---

## Dependency graph

```
Phase 0  protect + unblock ─────────────┐
                                         ├──> everything else
Phase 1  toggle compliance ─────────────┘

Phase 2a panel anchoring ✅ ─> Phase 3 (media panel, center)   [unblocked]
                        └─> Phase 4 (weather panel, center) [unblocked]
Phase 2b font-token split ──> Phase 6b (font picker)

Phase 7a bind Super+D ──> Phase 7b remove walker
Phase 9  lock verified ──> remove hyprlock
```

Phases 3, 4, 5, 8, 9, 10 are independent of each other once 0-2 are done.

### What quickshell ends up replacing

| Tool | Function | Status |
| --- | --- | --- |
| `waybar` | bar | ✅ replaced, package removed |
| `mako` | notifications | ✅ replaced, package removed |
| `walker` | app picker | ✅ replaced — `Super+D` opens the quickshell launcher; **package uninstall still pending the owner's sudo** |
| `awww` / `swww` | wallpaper rendering | ✅ replaced by the QML crossfade, unreferenced; **uninstall pending sudo** |
| `nsxiv` (as wallpaper browser) | wallpaper browsing | ✅ unbound — one wallpaper entry point now. Package still installed (never *replaced*, just unused) |
| `scripts/switch-wallpaper.sh` | wallpaper *picking* | ✅ as designed — stays the backend CLI (`get`/`list`/`set`); the picker UI is now native |
| `pywal` | palette extraction | ✅ **replaced by wallust** 2026-09-03. `python-pywal16` stays installed transitively as the rollback path |
| `hyprlock` | lock screen | ⚠️ built, **still never invoked for real** — Phase 9a, needs the owner at the keyboard |
| `hypridle` | idle → dim/lock/dpms/suspend | ❌ **not started, still running and owning the idle chain** — Phase 9b |
| `wlogout` | power / session menu | ❌ not started, still bound to `Super+Shift+E` — Phase 9c |
| `copyq` | clipboard manager | ✅ retired — verified double-capturing with the plugin. `Super+Shift+V` now opens the plugin. Package and data left in place as the undo path |
| `scripts/watch-monitors.sh` | repaint wallpaper on hotplug | ⚠️ still autostarted. Believed redundant now the QML `Variants` owns outputs, but **unverifiable without a second display** |

**Not replaced, and not candidates:** `pywal` (generates the palette
quickshell reads — it is the *input* to the theming, not a competitor),
`hyprpicker` (colour picking; every surveyed shell just shells out to it),
and the KDE polkit agent (see Out of scope).

---

## Already done (2026-09-01) — do not redo

Recorded so a later reader doesn't re-derive or re-litigate these.

- **Bar widgets trimmed.** `active-window`, `agents`, `microphone`, `news`,
  `costs` dropped; `toggles` kept. Removed from **both**
  `~/.local/state/quickshell/shell.json` and `shell.qml`'s
  `builtinShellConfig`. Their `.qml` + manifests remain on disk, so re-adding
  any one is a single array entry.
- **`mako` removed**, and with it a bug that had never been diagnosed:
  `/usr/share/dbus-1/services/fr.emersion.mako.service` declared
  `Name=org.freedesktop.Notifications`, so D-Bus *activated* mako on the
  first notification of every boot and it won the race against quickshell —
  regardless of its disabled systemd unit and its removal from hyprland
  autostart. **Quickshell's notification daemon had therefore never actually
  been the live handler.** It is now (verified: bus owner is the quickshell
  PID and `notify-send` renders).
- **`waybar` package removed.** Used plain `-R`, not `-Rs`: `-Rs` would also
  have taken `gpsd`, which GeoClue2 can use as a location source for the
  weather widget (Phase 4). Repo-side cleanup remains — Phase 0.
- **Regression from the mako removal, found and fixed.** With mako gone, the
  only remaining D-Bus-activatable provider of
  `org.freedesktop.Notifications` was plasma-workspace's
  `plasma_waitforname`, so `notify-send` blocked until the activation
  timeout (~25s) whenever quickshell was down. `toggle_main` calls
  `notify-send` on **every** on/off/toggle, so every toggle — bar,
  `menu.sh`, keybind — would have hung for ~25s exactly when the shell was
  broken. Fixed with a `toggle_notify()` wrapper in `toggles/lib.sh`
  (`timeout 2 notify-send … || true`), routing all five call sites through
  it. Measured 15ms after.
- **`Ui/PanelSlider.qml` used `bar.foreground`, which does not exist.**
  `Bar.qml:50` exposes `barForeground`; three color properties silently
  resolved to undefined on every start. **Third occurrence of this exact
  naming mismatch** — `Tray.qml:25` already carried a warning comment. Fixed,
  with a comment naming the trap. Restart is now warning-free.
- **`prompts.md` updated** with both weather SPEC additions, verbatim.

---

## Phase 0 — Protect the work and unblock testing · **S**

Nothing here is a feature; all of it removes risk that compounds later.

- [~] **Run `./sync.sh`.** Originally: `configs/quickshell/` and `TODO.md`
  are untracked; TODO.md already vanished once and was only recovered by
  replaying Claude Code session transcripts — a trick that would **not**
  have worked for the research docs, which were written by subagents and
  never passed through a transcript. The single highest-risk item in the
  whole roadmap.
  - **2026-09-02, partly done:** all 272 files are **staged** (`git add .`
    ran, so every research doc is now a blob in `.git/objects` and survives
    a filesystem accident). The commit itself did **not** happen — it is
    GPG-signed and pinentry times out under automation. **Still needs a
    human to run `./sync.sh`**, and that run must also pick up everything
    written after the staging.
- [x] **Set Hyprland `misc:allow_session_lock_restore = true`** — done
  2026-09-02 in `configs/hyprland/hyprland_misc.lua`. With it false, a QML
  error while the session is locked was an unrecoverable lockout, which is
  why `Lock.qml` had never been tested since Phase 7. The Lua config
  auto-reloaded and `hyprctl getoption` now reports `bool: true, set: true`,
  so **Phase 9a is unblocked** and its test is now routine rather than risky.
- [x] **Reconcile `shell.qml`'s `builtinShellConfig` with the live layout** —
  done 2026-09-02. The tracked default was missing tray, battery, indicators,
  keyboard-layout and system-update, so a fresh machine or a deleted state
  file reproduced the wrong bar (see `07 §0a`). All five added to `right`,
  with a comment naming the state-file override so the next reader knows both
  places must change together.
- [x] **Finish the waybar decommission** — done 2026-09-02. `install.sh`
  entry, `configs/link.sh` line, the `~/.config/waybar` symlink and
  `configs/waybar/` are all gone; `scripts/switch-wallpaper.sh` had already
  been cleaned in an earlier pass. **`toggles/waybar-status.sh` was NOT dead
  code** — this roadmap's "confirm nothing else consumes it" caught it:
  `Toggles.qml:51` is a live consumer. Renamed to `toggles/status.sh`, with
  its caller and every stale comment updated, rather than deleted.
  Note `configs/waybar/` went to the trash (`rm` is aliased to `trash`
  here), so it is recoverable rather than permanently gone.

**Acceptance — 3 of 4 met 2026-09-02.** `hyprctl getoption
misc:allow_session_lock_restore` returns `true` ✅; `builtinShellConfig` now
matches the live layout entry-for-entry ✅ (the deleted-state-file restart was
verified by diffing the two lists, not by deleting the live file); waybar is
fully unreferenced ✅. **`git log` does not yet show the research committed** —
that is the outstanding half of the sync item above.

---

## Phase 1 — Toggle-contract compliance · **M**

This phase *is* the SPEC's "make sure settings that require changes in
dotfiles are properly done and not just hacked together". Reference:
`02-toggle-contract.md` §5.

- [x] **`toggles/toggle-bluetooth.sh`** — done 2026-09-02. One addition
  beyond the plan: `turn_on` runs `rfkill unblock bluetooth` first, because
  `bluetoothctl power on` fails silently against the soft-blocked adapter
  that `toggle-offline.sh` leaves behind.
- [x] **`toggles/toggle-wifi.sh`** — not in the original plan, but
  `Network.qml` ran `nmcli radio wifi` inline exactly the same way
  bluetooth did, so it was the same violation. Goes through NM rather than
  `rfkill block wifi` so the reported state is NM's own.
- [x] **`toggles/toggle-offline.sh`** — done 2026-09-02, **and the real bug
  is fixed and verified.** `nmcli networking off` + `rfkill block all`, with
  the three tunnel toggles torn down first. Going back online deliberately
  does *not* restore tunnels. Bluetooth input devices are not exempted
  (documented in the script; none paired).
  - **Verified by a live round-trip**, not by reading: with offline on,
    `nmcli networking` = `disabled`, **both `wlan0` and `enp0s31f6` went
    `DOWN`**, and `ping 1.1.1.1` was unreachable; off restored
    `connectivity=full` with the IP back. The old `rfkill`-only version
    could never have taken `enp0s31f6` down.
  - **One trap worth recording:** `check` cannot use `grep -v blocked` on
    `rfkill --output SOFT` — `"unblocked"` *contains* `"blocked"`, so the
    negated form matches nothing and reports offline unconditionally. Uses
    `grep -qx unblocked` instead.
- [x] **Rewire `Network.qml`** — done 2026-09-02. All six state changes now
  shell out to `toggles/*.sh`, and all six reads use the same scripts' `get`.
  The only `nmcli` left in the file is the read-only monitor below.
- [ ] **Adopt native bindings for *reading* only.** Quickshell 0.3.1 ships
  `Quickshell.Bluetooth` and `Quickshell.Networking` (both verified present
  on disk; neither is on the stale docs site). Bind device lists, adapter
  state, and device battery to those instead of polling `bluetoothctl`;
  keep writes on the toggle scripts. `BluetoothAdapter.enabled`/`.discovering`
  are writable and `BluetoothDevice` exposes `battery`/`connected`/`paired`
  — see `05 §3`. Audio-profile (A2DP/HSP) switching has no native property
  and stays on `wpctl`/`pactl`.
- [x] **Replace the flat 10s connectivity poll** — done 2026-09-02. A
  long-lived `nmcli monitor` Process (400ms debounce, auto-restart if NM
  itself restarts) drives updates, with the old poll kept at 30s as a
  fallback for what NM does not report (bluetooth power). `CONNECTIVITY` is
  read in `network-details.sh` and surfaced as a `connectivity` property plus
  a "Status" row reading `Online` / `No internet` / `Captive portal` /
  `Offline`, shown *even when a device is connected* — which is exactly when
  a device-state check lies.
- [x] **Bar icon now answers the SPEC's "lan/wifi?"** — five states
  (offline / tunnel / disconnected / limited / lan-vs-wifi). All codepoints
  cmap-verified, which caught two bad guesses: `U+F796` and `U+F6FF` are
  **absent** from 0xProto Nerd Font, and `U+F0AA8` exists but is
  `md-credit_card_refund_outline`, not `md-lan_connect` (that is `U+F0318`).
  Exactly the failure Ground rule 4 exists to prevent.
- [ ] Native `Quickshell.Bluetooth` / `Quickshell.Networking` bindings for
  device lists and device battery — **not done**, and deliberately deferred:
  the panel has no BT device list to bind yet, so this is new UI rather than
  a rewiring. The reads it would replace already go through the toggle
  scripts. Pick it up with the bluetooth-device-battery item in Phase 12.

**Acceptance — met 2026-09-02.** `toggles/menu.sh` globs `toggle-*.sh`, so it
drives bluetooth, wifi and offline mode with no wiring; `Network.qml`
contains no `rfkill`/`bluetoothctl` invocation and no `nmcli` write; offline
mode verifiably drops the wired interface (see the round-trip above).

---

## Phase 2 — Structural blockers · **M-L**

Both gate later phases. Neither is user-visible on its own.

### 2a. Panel anchoring · **M**, gates Phases 3 and 4 — ✅ **DONE 2026-09-02**

Was: every hover panel anchored top-right, so the mid-bar clock trigger sat
~950px from its own panel, blocking the SPEC's two centre-section panels
(datetime, media).

The two earlier attempts had both chased the wrong thing — a different
*coordinate source* — when the actual defect was **reactivity**:

- `mapToGlobal` — Wayland gives clients no true global coordinates.
- `mapToItem(bar.contentItem, …)` — correct arithmetic, evaluated once
  before `RowLayout` had laid anything out, then never recomputed.

**What worked** (the roadmap's own untried third approach):

- [x] `Bar.layoutRevision` — an int bumped by each section's
  `onXChanged`/`onWidthChanged`.
- [x] `BarWidget.barX` — the widget's laid-out x, republished imperatively
  whenever its own geometry, its ancestors' geometry, or the bar's width
  changes. **Never a binding**: `mapToItem` walks ancestor positions QML
  does not track as dependencies.
- [x] `HoverPanel.anchorWidget` — set it to the trigger and the panel opens
  centred beneath it, clamped to the screen edges; leave it null and the
  panel keeps the right-anchor. Centralised, so Phase 3's media panel and
  Phase 4's weather panel are one property each.

**Two bugs found while building it, both of which would have looked like
"the approach doesn't work":**

1. **Recomputing inline is not enough — it must be deferred.** The signals
   announcing a layout change fire *during* the layout pass, when the
   ancestor chain is half-settled; reading `mapToItem` there returns the
   pre-layout position and nothing fires again. `barX` now settles on a 16ms
   one-shot Timer that coalesces a burst of signals into one read. Symptom
   before the fix: the panel was correct at startup and then stuck at its
   old position after any live layout change.
2. **`margins.top: barSize + 4` double-counted the bar.** The bar sets
   `exclusiveZone = barSize`, so a top-anchored layer surface *already*
   starts below the bar. Every panel had been sitting 30px lower than
   intended, with a 34px dead gap between trigger and panel that hover had
   to cross. Verified directly: `top: 4` lands the panel at y=34 under a
   30px bar. Now 4px for every panel.

Both `anchors` and `margins` moved into `HoverPanel` itself and the
redundant per-panel overrides were deleted from all 8 widgets, so there is
one place that decides panel geometry.

**Acceptance — met, verified with a real pointer.** The clock panel opens at
x=493 centred under a clock trigger at ~649 (it was pinned to the right edge
at 1592 before), and hover transit trigger→panel works and *stays* open 1.5s
later — well past the 350ms grace, so the panel itself is holding it. Live
layout change verified without a restart: widening the left section moved the
panel 489→611 and restoring it moved it back. Right-anchored panels all still
land flush at right=1912, so no regression.

**Open, not decided:** right-section panels still anchor top-right. That was
originally "the one variant that actually works", which is no longer true —
they could now open under their own triggers too. Kept as-is because a shared
landing spot has independent merit for transit between adjacent triggers, and
because changing 8 panels' behaviour is a UX call, not a bug fix.

### 2b. Font-token split · **M**, gates Phase 6b — ✅ **DONE 2026-09-02**

`Style.font.family` drew **both** body text and every icon glyph, with the
family pinned to `0xProto Nerd Font`. That is why the font picker could not
ship: pointing the single family at a non-Nerd font silently replaces every
icon with whatever other installed font happens to contain that codepoint —
a *wrong* glyph, not a missing one, and no QML error either way.

- [x] **Two families in `Commons/Style.qml`**: `fontFamily` (UI/body text,
  destined to become user-selectable) and `iconFontFamily` (every glyph,
  stays pinned to a Nerd Font forever).
- [x] **Swept every glyph call site onto the icon token** — 75 glyph-bearing
  lines across 25 files, found by scanning for Private-Use-Area codepoints
  and `\u{f…}` escapes rather than by eye.
- [x] **`fc-match` verification kept, and moved to the icon token**, where it
  matters: fc-match always answers with *something*, so a reply that is not
  the requested family means 0xProto is missing and every glyph is about to
  be a substitution. That case now logs a warning instead of passing
  silently. The UI family gets its own separate resolve, so a bad user font
  choice degrades text only and cannot take the icons with it.

**NAMING DEVIATION from this roadmap.** It prescribed `Style.font.ui` /
`Style.font.icon`. **`font.icon` already exists as an int *size* token (14)**
with many call sites, so those names collide. Used `font.family` /
`font.iconFamily` instead — which also leaves every body-text call site
untouched, making the sweep much smaller.

**The axis that nearly got missed:** `Bar.qml` exposes
`fontFamily: Style.resolvedFontFamily`, and bar widgets use it for **glyphs**
as well as label text. Sweeping only `Style.font.family` would have left
every bar glyph on the user-selectable family — precisely the breakage this
phase exists to prevent. `Bar.qml` now also exposes `iconFontFamily`.

**Done structurally first, then mopped up.** Four icon-*rendering* components
were fixed once each, covering most call sites: `Ui/OpticalGlyph.qml`,
`Ui/BarIconButton.qml` (icon-only by construction, so `BarIndicator`
inherits the fix), `Ui/PanelActionButton.qml`, plus `Osd.qml`'s
`iconMetrics` (the drawn Texts inherit it via `font: iconMetrics.font`) and
`NotificationCard.qml`'s two glyph slots.

**The rule for glyphs concatenated with other text, applied consistently:**

- glyph + **user** text → **split into two Texts** (a Row), so the user's own
  string follows their UI font. Two sites: `Clock.qml`'s reminder label and
  `Media.qml`'s player identity.
- glyph + **digits/units** → leave as one Text on the **icon** family.
  Numerals render fine in a Nerd Font, and splitting a six-token string like
  `System.qml`'s bar stats into alternating Texts is churn for no gain.

**Acceptance — met, verified visually, which is the only way.** A missed
site produces no error, so clean logs prove nothing. Set
`Style.fontFamily = "DejaVu Sans"`, restarted, and captured the bar plus all
eight panels, an alert card and a notification toast: every glyph still
rendered correctly while all body text visibly changed family. Reverted, and
`Style.qml` diffed byte-identical to its pre-test state.

**Phase 6b (the font picker) is now unblocked** — and note the ordering
existed for exactly this reason: shipping the picker first would have broken
every icon in the shell.

---

## Phase 3 — Media widget · **L** — ✅ **DONE 2026-09-02**

Was 82 lines: a play/pause glyph, a title, and a tooltip. Now a live cava
spectrum in the bar plus a rich hover panel. Detail in
`03-media-visualizer.md`.

- [x] **`Commons/Cava.qml`, ref-counted.** `output.method=raw`,
  `data_format=ascii`, `raw_target=/dev/stdout`, read via `Process` +
  `SplitParser`, config generated to `$XDG_RUNTIME_DIR/quickshell-cava.conf`
  so it never collides with `~/.config/cava/config`. The config text is
  passed as an **argv element**, not heredoc'd into the shell script, so
  nothing in it can be re-interpreted.
  - **Lives in `Commons/`, not `services/`, and that is deliberate.**
    `Commons` is the only real QML *module* here (`module qs.Commons`), and
    a module is what makes a singleton actually singular. The lowercase
    `services/` directory holds injected *instances* precisely because
    relative-path singleton imports were creating one copy per importer —
    see `services/BarWidgetRegistry.qml`'s header.
- [x] **Ref-counting via `Commons/CavaRef.qml`.** The bar widget holds a ref
  while visible *and* playing; the panel holds a second while open.
  **Verified live:** playing with the panel closed → cava up; paused with
  the panel closed → cava **exits**; resumed → restarts. Paused *with the
  panel open* correctly keeps it alive on the panel's own reference.
- [x] **`Repeater` + `Rectangle` + `Behavior on height`.** No
  Canvas/Shape/ShaderEffect, no compiled C++ plugin.
- [x] **Rich hover panel**: album art from `trackArtUrl` (with an fa-music
  fallback for players that publish none, and for URLs that fail to load),
  title/artist/album, transport, loop cycling None→Playlist→Track, shuffle,
  and a player picker that only appears when more than one player exists.
  Clicking the pinned player unpins it.
- [x] **Seek bar.** `MprisPlayer.position` does not tick on its own; a 1s
  Timer emits `positionChanged()` to force the re-read, and only while the
  panel is open. The slider ignores the poll while dragging, or the knob
  would be yanked back under the pointer.
- [x] **Moved `bar.media` from `right` to `center`** per SPEC, in **both**
  `shell.json` and `shell.qml`, plus the manifest's `defaultSection`.

**One deliberate deviation from the research doc: `sensitivity=300`, not
30.** The doc's value is DankMaterialShell's, and DMS re-normalises the
values in QML afterwards. Feeding music-shaped noise through a null sink and
measuring: sensitivity 30 peaked at **7/100** — a visualizer that never
visibly moves. 100 → ~24, 300 → ~65, 450 → clipped. With
`ascii_max_range=100` a value is now directly "percent of bar height", so no
QML normalisation is needed and there is no autosens wobble.

**Also worth knowing:** cava emits a **trailing semicolon**, so a 6-bar
frame splits into 7 parts with the last empty. Read by index; do not assume
`parts.length === barCount`.

**The title is a fixed 200px, not `Math.min(implicitWidth, 220)`.** In the
centre section a width that tracked the title would shove the clock sideways
on every track change — the same jitter that got `active-window` dropped
from the bar.

**Acceptance — met, verified end to end** against a throwaway MPRIS player
and a silent null sink (default sink temporarily routed there, so the test
made no audible noise; both restored afterwards):
- **Bars move with audio** — sampled pixel heights across frames change per
  band (e.g. bar 1: 3→7→0 while bar 2 went 3→3→7).
- **CPU returns to idle** — cava exits on pause, restarts on resume.
- **The panel shows art, seek and controls for a real player** — art
  rendered from `file://`, position advanced 1:50→1:57 over 7s, and **real
  pointer clicks** drove every control: pause/play, next, previous, shuffle,
  the full loop cycle, and a seek drag that reached the player as
  `SetPosition`.

**Testing note for later phases:** mpv does **not** publish MPRIS without
the `mpv-mpris` package, which is not installed. The throwaway D-Bus player
used here needs no package (python-dbus and pygobject are both present).

## Phase 4 — Weather widget rebuild · **M-L** — ✅ **DONE 2026-09-02**

Was 73 lines: one `wttr.in` call, a glyph, a tooltip. Now the SPEC's three
tiers. Detail in `08-weather.md` §6.

- [x] **Switched to Open-Meteo.** One request returns current + hourly +
  daily, no key, HTTPS, and it takes only lat/lon — never a city name or an
  IP lookup, which is the whole lever for not leaking location.
- [x] **`toggles/toggle-weather-location.sh`** with the layered precedence
  and `get|label|on|off|toggle` plus `set|clear|resolve|coords|source`.
- [x] **Coordinates rounded to 2dp (~1.1km) before any network call** — in
  the toggle, on *every* path, so an unrounded value cannot reach a URL.
  Verified: `set 51.50735 -0.12776` stores `51.51,-0.13`.
- [x] **Panel content** — current (temp, feels-like, humidity, cloud, UV,
  wind speed + direction + gusts, precipitation, pressure), a rolling 24h
  hourly sparkline, and the 3-day forecast.
- [x] **"Windy" derived**, since it is not a WMO code: `weather_code` gives
  the sunny/rain axis and `wind_speed_10m_max >= 39 km/h` (Beaufort 6,
  chosen because it is a real scale boundary) overrides the label and glyph.
- [x] **`wind_direction_10m` mapped** to an 8-point compass label plus a
  rotated `md-navigation` arrow. The label names where the wind comes *from*
  (meteorological convention); the arrow points where it is going.
- [x] **Never renders** place name, coordinates, timezone or
  sunrise/sunset — and this is **structural, not disciplinary**. See below.
- [x] **Widened to 460** with the hourly series as a sparkline (temp line +
  rain-probability bars on a shared axis). Tabs stay rejected.
- [x] **`iconFor()` re-keyed, not replaced** — same verified glyph set,
  keyed off the WMO enum instead of wttr.in's free-text condition strings.

### The privacy guarantee is enforced in the shell script, not in QML

`weather-fetch.sh` fetches, then **whitelists** the fields before emitting
JSON. Open-Meteo's response echoes back `latitude`, `longitude`, `timezone`,
`timezone_abbreviation` and `elevation`; sunrise/sunset are simply never
requested. `Weather.qml` therefore never *receives* a location, so no future
edit to it can leak one — which is what doc 08 §2a asked for ("a stronger
guarantee than 'remember not to bind it'").

The script also **asserts the whitelist held** and emits an error rather
than the payload if a banned key ever appears. Unit-tested against poisoned
payloads: `latitude` at top level, `timezone` nested inside `current`, and
`sunrise` inside a `daily[]` entry are all caught.

`source` is reported to the UI ("manual location" / "timezone estimate" /
"IP estimate") — that says *how* the location was determined, never where.

### Two roadmap claims about GeoClue that are wrong, verified on this machine

The plan justified GeoClue as "WiFi-based and immune" to the VPN problem
that poisons IP geolocation. **Neither half holds here:**

1. **GeoClue resolved via `GeoIP (ichnaea)`, not WiFi.** Mozilla's location
   service is gone, so there is no WiFi backend for it to use — it is
   exactly as VPN-poisoned as the IP tier it was supposed to replace.
2. **It returns nothing at all without an authorised agent process
   running.** With `geoclue-demo-agent` up it answered; with no agent it
   silently returned nothing. So the roadmap's planned
   `/etc/geoclue/geoclue.conf` whitelist entry would *not* have been
   sufficient on its own, and was deliberately **not** added to
   `install.sh`: a whitelist without a running agent is a half-measure, and
   the tier it would enable is no better than the IP tier anyway.

Consequence: in practice the automatic answer is the **timezone centroid**,
read offline from `/usr/share/zoneinfo/zone1970.tab`. That is the one
automatic tier a tunnel cannot poison — a better default than the roadmap
expected, for worse reasons than it assumed.

### `on` pins the resolved location rather than failing

First version had `turn_on` return 1 when no coordinates were stored. That
is a trap specific to this contract: `toggle_main` runs `on_fn` under
`set -e`, so a non-zero return **aborts before `toggle_set` and
`toggle_notify`** — making the entry a silent no-op in `menu.sh`, with no
notification, which is precisely what `toggle_notify` exists to prevent.
Every other toggle in the repo has an `on_fn` that cannot fail; this was the
first that could. `on` now pins whatever the chain currently resolves to,
which always succeeds and is the more useful reading of "turn manual mode
on" anyway. **Any future value-carrying toggle must keep `on_fn` infallible.**

### Automatic location was demonstrably wrong here, so a manual override is set

Worth recording because it is the strongest possible argument for the manual
tier existing: on this machine the two automatic tiers **disagreed with each
other and both were wrong**. GeoIP said London (51.51, -0.13); the timezone
centroid said Berlin (52.50, 13.37); the owner was in **Glasgow**. Manual
override now set to `55.86,-4.25`, and the panel labels it "manual
location". Clear it with `toggle-weather-location.sh clear` when travelling,
or re-`set` it.

**Acceptance — met.** Panel shows all three tiers; no place name,
coordinate, timezone or sunrise/sunset appears anywhere in the UI; the
location comes from a stored value rather than the request IP, so bringing
up a VPN cannot change it. Fallbacks verified: with the network blocked the
script serves the cache with `stale: true`, and with the manual override
removed it falls through to the timezone tier.

## Phase 5 — Clock panel completions · **M** — ✅ **DONE 2026-09-02**

- [x] **Pomodoro timer with notifications.** `scripts/pomodoro.sh` owns all
  of it: `start [work] [break] [long] | stop | pause | resume | skip | toggle
  | status [--json]`. Defaults 25/5, long break 15 every 4th cycle,
  deliberately not configurable beyond `start` — the SPEC asks for a
  pomodoro, not a pomodoro settings screen.
- [x] **Bar indicator while running** —
  `plugins/bar/indicators/Pomodoro.qml`, same shape as `Reminder.qml`,
  registered in `Indicators.qml`. md-timer_sand while focusing, md-coffee on
  a break; click cycles start/pause/resume.
- [x] **"Remind me in X" wired into the clock panel.** Quick chips for
  5/10/15/30/60 minutes plus `…`, which summons the existing two-step
  `plugins/reminders/ReminderFlow.qml` — built in port Phase 6 and never
  wired to anything until now. Active reminders are listed with their
  countdown and fire time, with a "clear all" row.
- [x] Clock panel widened 320 → 360 for the new rows.

### The phase countdown lives in systemd, not in the shell

Same design as `reminder.sh`: each phase is a `systemd-run --user` transient
timer, so a finished focus block still notifies if quickshell was restarted
mid-session, and the whole thing is drivable from a keybind with no GUI.

**Three things that had to be got right, each of which failed first:**

1. **`AccuracySec=1s` is mandatory.** systemd's default timer accuracy is one
   minute and it coalesces wakeups — measured, a 5s timer fired 10s late.
   Invisible on a reminder, very visible on a 5-minute break.
2. **Every armed phase needs its own unit name.** With one fixed name, the
   firing unit *is* `quickshell-pomodoro.service`, so the `cancel_timer`
   inside `arm` stopped the very service that was mid-`_advance` — it killed
   itself before it could arm the next phase. The journal showed "Started …
   _advance" and "Stopping … _advance" in the same second, state advanced to
   `break`, and no timer existed. Units are now `quickshell-pomodoro-<epoch>`
   and `cancel_timer` only ever stops `*.timer`, never `.service`.
3. The self-chain itself was **verified in isolation before building on it**
   (a three-stage chain of transient `--collect` units, each arming the
   next), because "fires once then silently stops" would have been very hard
   to attribute later.

### Reminders are now audible, large, and manually dismissed

Owner's call mid-phase: *"reminders should be both audio and visual,
preferably big in top left and manually dismissed."* An ordinary toast is
the wrong shape for an elapsed timer — it auto-expires, so a reminder that
fires while you are looking elsewhere is simply gone.

- **New `plugins/alert/` overlay** — a large top-left card, accent-bordered,
  that stays up until clicked. Multiple alerts **stack** rather than
  replacing each other (two timers can elapse in the same minute).
- **New `scripts/alert.sh`** — plays
  `freedesktop/stereo/alarm-clock-elapsed.oga` (canberra → paplay → pw-play)
  and summons the card over IPC, **falling back to a plain notification if
  quickshell is not running**, so an alert is never silently lost. The sound
  is played by the script, not by QML, for the same reason.
- **Two tiers, on purpose.** Only *elapsing* events become alerts (reminder
  fires, pomodoro phase ends). Confirmations — "reminder set", "pomodoro
  stopped" — stay ordinary toasts; making those blocking would train you to
  dismiss alerts without reading them.
- `keyboardFocus: OnDemand`, not `Exclusive`: an alert must not steal the
  keyboard the instant it appears and eat keystrokes mid-sentence.

**A plugin's `close()` must never call `shell.hide()`.** `shell.hide()`
invokes the plugin's own `close()`, so that recurses until the stack blows
(`RangeError: Maximum call stack size exceeded`) — and the damage is
delayed: the shell's `openPanelIds` entry is then never cleared, so every
*later* `summon` returns "ok" and silently delivers nothing. Symptom was an
overlay that worked exactly once. `ReminderFlow.qml` already splits
`close()` (shell-invoked, just closes) from `dismiss()` (plugin-invoked,
closes *and* tells the shell); follow that split in every overlay.

**Acceptance — met, verified end to end.** A 1-minute reminder and a 1-minute
pomodoro focus phase were armed together and both fired from real systemd
timers into stacked, audible, still-present alert cards. Every clock-panel
control was driven with **real pointer clicks**: play → `Focus 24:58 ·
pomodoro 1`, pause → paused, stop → off, and the 10m chip armed a reminder
visible in the panel list. Repeated summon/dismiss cycles verified after the
recursion fix (three rounds, no leak).

**Follow-up for the owner:** `scripts/link.sh` has not been re-run, so
`/usr/local/bin/alert` and `/usr/local/bin/pomodoro` do not exist yet (it
needs sudo). Nothing is broken — both scripts call each other by absolute
path precisely so they work before linking — but the bare `pomodoro` /
`alert` commands and any keybind using them need that run first.

## Phase 6 — Panel completions · **M**

### 6a. Notification history · **S-M** — ✅ **DONE 2026-09-02**

- [x] **History now renders with `NotificationCard.qml`** — the same card the
  toasts use — instead of the two plain `Text` elements that were there. The
  card already did everything the SPEC asks of this list: an image slot with
  app-icon and glyph fallbacks, urgency colouring, and a click action.
- [x] **`cardClicked()` wired** to `openEntry()`, which opens the source.
- [x] **Checked that the stored rows retain the rich fields** — they do. A
  history file carries `app`, `appIcon`, `image`, `glyph`, `execArgv`,
  `urgency` and `timestamp`, so nothing had to change in the daemon or in
  `NotificationLogic.js`. This was the item most likely to turn into daemon
  work and it turned out to be free.

**Opening the source needs three tiers, not one.** A stored entry is no
longer a live notification — its D-Bus action object is gone — so:

1. `execArgv`, which the daemon persists precisely so restored toasts stay
   clickable. This is the only *real* action carrier.
2. `DesktopEntries.byId()`, for the case where the app id is a real
   desktop-file id.
3. A name matcher, because **neither of the above actually works for a
   typical notification**: `app_name` is a display name. Verified live —
   a notification from `ghostty` stores `app: "ghostty"` while the desktop
   file is `com.mitchellh.ghostty.desktop`, so `byId` and
   `heuristicLookup` both missed. The fallback matches case-insensitively
   on entry name, id, or the id's last dotted segment (which covers
   reverse-DNS ids). **Verified by a real click launching the app.**

Right-clicking a card clears the history; per-entry removal is deliberately
not offered, because the daemon owns those files and the panel removing one
would desync it.

### 6c. Audio deafen · **S** — ✅ **DONE 2026-09-02**

- [x] One control muting sink and source together, in the AudioIO panel.

`deafened` is **derived** (`muted && micMuted`), not stored, so it stays
correct when either side is muted individually or from outside the shell — a
headset button, a keybind, another app. Undeafening sets both to unmuted
rather than restoring a remembered prior state: mute can change externally
while deafened, and replaying a stale snapshot would silently re-mute a
device the user had just unmuted.

**Verified with real clicks:** both channels muted together and both
restored, with volume levels preserved (0.65 / 1.00) across the round trip.

### 6b. Display panel · **M** — ✅ **DONE 2026-09-02**

- [x] **`toggles/toggle-font.sh`** with `get | size | label | list | toggle |
  set <family> | set-size <n>`. `list` enumerates via `fc-list` — 4174
  families here.
- [x] **Owns every call site**: ghostty, zed (**all three** key pairs,
  including the terminal block's own `font_family`/`font_size` at
  `settings.json:44-45` that the old regex missed), emacs `early-init.el`,
  discord `wal.theme.css`, nvim `options.lua`, and quickshell's own
  `Style.fontFamily`. It pointedly does **not** touch `iconFontFamily` —
  that would put every glyph in the shell on a substituted font.
- [x] **Deleted `Display.qml`'s `setFont`/`setFontSize` sed calls and the
  4-entry hardcoded `fontChoices`.** No QML in this repo shells into a
  dotfile any more.
- [x] **`toggles/toggle-monitor-scale.sh`** — reads the live mode and
  position from `hyprctl monitors -j` and reapplies them *with* the new
  scale, instead of `preferred,auto` (which discards resolution, refresh and
  position). Applies live, confirms the compositor took the value, and only
  then persists into `hyprland_monitors.lua`.
- [x] **Brightness now uses `Ui/PanelSlider.qml`** instead of a hand-rolled
  Rectangle + MouseArea, so it drags and themes like every other slider.

**Two silent bugs found while replacing this code:**

1. **`hyprctl keyword` does not work here at all.** This repo drives
   Hyprland from Lua configs, and against a non-legacy parser `hyprctl
   keyword` prints *"keyword can't work with non-legacy parsers. Use eval."*
   and **exits 0**. The Display panel's scale buttons had therefore been
   doing nothing while reporting success. `hyprctl eval` with an
   `hl.monitor{}` call is the form that applies. (Same family as the
   `hyprctl dispatch` Lua-syntax trap in Appendix A.)
2. **`installed_families | grep -qxF "$x"` is wrong under `set -o
   pipefail`.** `grep -q` exits on first match, upstream dies of SIGPIPE,
   and pipefail turns that into failure — so the font guard rejected every
   family, including installed ones. Read the list into a variable first.

**A hover panel could not host a text field.** `Ui/HoverPanel.qml` hard-set
`keyboardFocus: None`, so the font search box silently swallowed every
keystroke. Added an opt-in `acceptsKeyboard` property (default false,
`OnDemand` when set) rather than changing all nine panels: a panel that
grabbed the keyboard on open would pull focus off whatever you were typing.
Only the Display panel opts in.

**Acceptance — met, verified end to end with real input.** Typing "iosevka"
into the picker filtered 4174 families down to the Iosevka variants, each
row **rendered in the font it names** so the list previews itself; clicking
one applied it across all six configs; the shell restarted into Iosevka with
**every glyph still correct** (Phase 2b's payoff, exercised through the real
picker); and `set "0xProto Nerd Font"` reverted all six files
byte-identically. Monitor scale was round-tripped 1 → 1.25 → 1 live, with
`hyprland_monitors.lua` updated for `eDP-1` only and DP-1/DP-2 untouched.

**Known limitation, deliberate:** `set-size` does not touch quickshell.
`Style.qml` carries a *scale* of absolute pixel sizes (caption 10, body 12,
heading 16 …) tuned to a 30px bar, not a single size — writing 16 into it
would not mean what it means in an editor. Its `fontBaseSize` property is
declared and unused; wire that up first if a shell-wide size control is
ever wanted.

## Phase 7 — Finish replacing walker · **M** — ✅ **DONE 2026-09-02**
*(one step left for the owner: the package removal itself)*

**This was what "App Menu (replacing walker)" actually required.** The
quickshell launcher had existed since port Phase 5 but had **no keybind**,
so `Super+D` still opened walker and removing the package would have left no
keyboard launcher at all.

- [x] **7a. `Super+D` rebound** in `hyprland_keybindings.lua` from
  `nc -U /run/user/1000/walker/walker.sock` to
  `quickshell ipc -p ~/.config/quickshell call appsearch toggle`.
  **Verified by actually pressing it** (the bind is a Lua closure, so
  `hyprctl binds` reports only `dispatcher: __lua, arg: 24` and cannot be
  read — it has to be exercised): the launcher opened, typing "ghost"
  filtered to ghostty, and Escape closed it.
- [x] **`toggles/menu.sh` and `scripts/spawn-shimoji.sh`** moved off
  `walker --dmenu` onto **`scripts/picker.sh`**, a new pywal-themed
  `bemenu` wrapper. quickshell's launcher is an *application* launcher with
  no dmenu mode, so these two needed a real general-purpose picker rather
  than a shell IPC call. bemenu was chosen because it is the only
  dmenu-style picker already installed that has a Wayland backend.
  Verified: renders in the wallpaper palette and returns the selection.
- [x] **`scripts/switch-wallpaper.sh`'s walker-CSS block deleted.**
  `picker.sh` reads `~/.cache/wal/colors` at call time, so it follows the
  wallpaper with no regeneration step at all — strictly simpler than what
  it replaced.
- [x] **`hyprland_autostart.lua`**: both `walker --gapplication-service`
  **and `elephant`** removed. quickshell's launcher is part of the shell and
  needs no daemon.
- [x] **`configs/walker/` deleted**, its `configs/link.sh` symlink line
  removed, and `~/.config/walker` unlinked.
- [x] **`install.sh` cleaned**: `walker-bin` plus **all 13 `elephant*`
  entries**. elephant is walker's data provider and had no other consumer —
  `pactree -r elephant` showed only `walker-bin`.

**Remaining, needs the owner** (package removal is not something this
session can run):

```
sudo pacman -Rs walker-bin $(pacman -Qq | grep '^elephant')
```

Dry-run checked: that resolves to exactly **27 packages**, all walker/
elephant (including their `-debug` variants) and nothing else.

Note `walker` and `elephant` are still *running* in the current session,
started by the autostart lines before they were removed. They go away at the
next login regardless of when the packages are uninstalled.

**Acceptance — met apart from the uninstall.** `Super+D` opens the
quickshell launcher; nothing in `toggles/` or `scripts/` references walker
except historical comments; `configs/walker/` is gone.

## Phase 8 — Wallpaper switcher · **M** — ◐ **MOSTLY DONE 2026-09-02**

- [x] **`scripts/switch-wallpaper.sh` given a `get | list | set` CLI**, so a
  native picker can drive it instead of duplicating its pywal logic. The
  interactive fzf path is unchanged and still the default.
- [x] **Dropped the redundant renderer.** `awww-daemon` ran alongside
  quickshell's own QML crossfade — two renderers on the same layer.
  **Verified by killing awww-daemon and confirming the wallpaper still
  renders**, then removed it from `hyprland_autostart.lua` and `install.sh`.
  Deliberate tradeoff: the wallpaper is now painted by quickshell alone, so
  a dead shell means no wallpaper — already true of the bar, notifications
  and OSD.
- [x] **Animated the palette transition** — the roadmap's "cheapest
  high-payoff item". Every one of the 40-odd role colours in
  `Commons/Color.qml` is a binding on **five** root colours, so five
  `Behavior on color` blocks animate the whole palette. Guarded by an
  `animatePalette` flag that only arms after the first load, so shell start
  does not visibly animate from the hardcoded defaults.

### The bug this uncovered: nothing was watching the wallpaper symlink

`Background.qml` refreshes on `Component.onCompleted` **or over IPC, and
nothing else** — it does not watch `~/.cache/wal/wallpaper`. That was
invisible while awww painted on top of it, and became a hard failure the
moment awww was removed: the symlink changed, pywal regenerated, and the
screen kept showing the old wallpaper until the next shell restart.

Caught by actually looking at the screen after a change rather than trusting
the symlink. `set_wallpaper()` now pushes
`quickshell ipc call background set <file>` after updating the symlink, with
failure ignored — a dead shell just reads the symlink itself on next start.
The `sleep 30` that used to wait out awww's transition is gone with it.

**Verified end to end:** changing the wallpaper crossfades the image *and*
animates the palette (bar background went dark-plum with an orange accent to
match), and switching back restored the original palette.

### The native picker is wired, and there is now one entry point

- [x] **`plugins/image-picker/ImagePicker.qml` is finally in use.** 603
  lines ported in port Phase 6 and unused ever since, for want of a
  consumer. **`scripts/wallpaper-picker.sh`** is that consumer: it drives
  the overlay's `selectionFile`/`doneFile` handshake and hands the result to
  `switch-wallpaper.sh set`.
  - The handshake stays in **shell**, not QML, because that is what it was
    designed for — the overlay writes the chosen path to one file and
    touches another to signal completion — and it keeps the picker bindable
    to a key and usable without the bar.
  - Opens the carousel on the **current** wallpaper (`selectedImage`), not
    the first file alphabetically.
  - **Falls back to the fzf picker** if the shell is down, so the feature
    never simply vanishes.
  - Verified: cancel (Esc) closes cleanly and changes nothing; selecting
    runs the full chain through to a pywal regeneration.
- [x] **Three wallpaper entry points consolidated into one.** `Super+W`,
  `Super+Shift+W` (which opened `nsxiv` as an ad-hoc browser) and the
  Display panel's button all now go through `wallpaper-picker.sh`.
  `Super+Shift+W` is unbound.

### Still open

- [ ] **Per-monitor wallpaper assignment.**
- [ ] **`scripts/watch-monitors.sh`** — deliberately left in place.
  It exists only to work around awww's hotplug blindness, and
  `Background.qml`'s `Variants` over `Quickshell.screens` should make it
  unnecessary, but **that needs a real hotplug to confirm** and this machine
  has one output. Removing it unverified risks a blank screen on a newly
  plugged monitor. Revisit with Phase 11.
- [ ] `awww` package itself still installed (`sudo pacman -Rs awww`);
  nothing references it any more.

## Phase 9 — Session: lock, idle, power · **S then M** · *depends on Phase 0*

Everything that owns the session lifecycle. Deliberately sequenced: verify
the lock screen first, then take over the idle chain that *drives* it, then
the power menu that *invokes* it. Doing them together means a failure has
three possible causes.

Replaces `hyprlock`, `hypridle`, and `wlogout`.

### 9a. Verify the lock screen · **S**

`plugins/lock/Lock.qml` (PAM + `WlSessionLock`, visuals ported from
upstream's `LockView.qml` in Phase 7 of the port) is verified only by zero
QML errors, IPC responding correctly, and a throwaway non-locking preview
overlay. It has **never been engaged for real** — there was no safe way to
test unlock without risking a lockout. Phase 0 removes that risk.

- [ ] With `allow_session_lock_restore = true`, invoke for real:
  `quickshell ipc -p ~/.config/quickshell call lock lock`. **In person**,
  with a TTY reachable, confirm password entry and unlock.
- [ ] Point `configs/hyprland/hypridle.conf`'s `lock_cmd` at the quickshell
  lock instead of hyprlock (an interim step — 9b removes the file).
- [ ] Consider `fprintd` as a second PAM path (`configs/fprintd/` exists).
- [ ] **Only after all of the above**, remove `hyprlock`.

### 9b. Replace hypridle · **M**

`hypridle` (installed, running as PID 1708, autostarted from
`hyprland_autostart.lua:7`) currently owns the whole idle chain. Quickshell
0.3.1 can take it over: `Quickshell.Wayland` ships **`IdleMonitor`**
(`_IdleNotify`) with `timeout`, `isIdle`, `enabled` and `respectInhibitors`,
plus `IdleInhibitor` — verified present on disk. One `IdleMonitor` per
timeout maps 1:1 onto hypridle's `listener` blocks.

The chain to reproduce, from `configs/hyprland/hypridle.conf`:

| Timeout | Action | On resume |
| --- | --- | --- |
| 600s | `brightnessctl -s set 10` (dim) | `brightnessctl -r` |
| 900s | `loginctl lock-session` | — |
| 1200s | dpms off | dpms on |
| 1800s | `w \| rg -q ssh \|\| systemctl suspend` | — |

**Three things `IdleMonitor` does not give you — plan for them explicitly:**

1. **`before_sleep_cmd` / `after_sleep_cmd` are systemd sleep hooks, not
   idle events.** Locking before suspend and restoring dpms after resume
   need logind's `PrepareForSleep` D-Bus signal (or a
   `/usr/lib/systemd/system-sleep/` hook), not an idle timeout. This is the
   piece most likely to be forgotten, and losing it means the machine
   suspends **unlocked**.
2. **Inhibitor semantics differ.** `toggles/toggle-keep-awake.sh` holds a
   `systemd-inhibit --what=sleep:idle` lock, and its comment notes hypridle
   respects dbus/systemd inhibitors. Quickshell's `respectInhibitors` refers
   to the **Wayland** idle-inhibit protocol, which is a *different
   mechanism*. **Verify that keep-awake still actually works before
   removing hypridle** — if it doesn't, either have the idle logic query
   systemd inhibitors directly, or rework `toggle-keep-awake.sh` to also set
   the shell's own inhibit flag over IPC.
3. **The SSH guard** (`w | rg -q ssh || systemctl suspend`) must be carried
   over, or the machine suspends out from under an active SSH session.

- [ ] Build the idle chain as a quickshell service using `IdleMonitor`.
- [ ] Handle `PrepareForSleep` for lock-before-suspend and dpms-after-resume.
- [ ] **Verify `toggle-keep-awake.sh` still inhibits idle** under the new
  implementation.
- [ ] Carry over the SSH guard.
- [ ] **Run both in parallel first** — hypridle's timeouts raised well above
  quickshell's — so a failure means "quickshell didn't fire", not "the
  machine never locked". Only then remove `hypridle` from `install.sh` and
  `hyprland_autostart.lua:7`, and delete `configs/hyprland/hypridle.conf`.

**Acceptance:** dim/lock/dpms/suspend all fire at the right times with
hypridle stopped; the machine locks before suspending; keep-awake still
prevents all four.

### 9c. Replace wlogout with a native power menu · **S-M** — ◐ **BUILT 2026-09-03, awaiting real hyprctl reload + acceptance**

`wlogout` (installed, `/usr/sbin/wlogout`) is bound to `Super+Shift+E` in
`configs/hyprland/hyprland_keybindings.lua:7` as `wlogout -b 5 -c 35`, with
its config in `configs/wlogout/` and its package at `install.sh:356`.

**This was previously marked "not a candidate" in this roadmap, on the
grounds that upstream omarchy-shell's power panel deliberately has no
shutdown/reboot/logout buttons (that was wlogout's job there). That is a
*fidelity* argument, not a reason for this repo** — the SPEC's framing is
"we essentially want to build a DE using Quickshell", and a session/power
menu is a standard DE component. It is also the same shape as the walker
problem that was already chosen for replacement: a separate GUI window
popping up over the desktop, themed independently of everything else.

Genuinely easy — a full-screen `WlrLayer.Overlay` with a row of actions,
all shell-outs, no new Quickshell API:

| Action | Command |
| --- | --- |
| Lock | quickshell's own lock over IPC (**depends on 9a**) |
| Logout | `loginctl terminate-session "$XDG_SESSION_ID"` or `hyprctl dispatch exit` |
| Suspend | `systemctl suspend` |
| Hibernate | `systemctl hibernate` |
| Reboot | `systemctl reboot` |
| Shutdown | `systemctl poweroff` |

- [x] Build the overlay — `plugins/power/PowerMenu.qml`, 2026-09-03.
  Keyboard-navigable (←/→ + Enter, `Esc` to dismiss), pywal-themed via
  `Color.menu.*`, one `PanelWindow` instance with no explicit `screen` (same
  focused-output convention as `AppSearch.qml`). Glyphs resolved to glyph
  *names* via fontTools, not just cmap presence — one guess (assumed
  "power-sleep") actually resolved to `md-account_heart` and was caught by
  screenshot review, not by the cmap check alone.
- [x] **Confirm-on-destructive.** Logout/Reboot/Shutdown route through
  `Ui/ConfirmDialog.qml`; Lock/Suspend/Hibernate fire immediately (no data
  loss on either). Lock still shells out to `loginctl lock-session` rather
  than the quickshell lock plugin directly — deliberate, see the file's own
  header: only hypridle answers logind's Lock signal today (Phase 9a/9b
  unstarted), and `loginctl lock-session` stays correct across that
  transition since it's the *signal owner* that changes, not this button.
- [x] Rebind `Super+Shift+E` — `hyprland_keybindings.lua` now calls
  `quickshell ipc call powermenu toggle`. **Not yet applied to the live
  compositor** (needs `hyprctl reload` or a relogin).
- [ ] **Not yet verified end-to-end.** IPC open/close and a `grim`
  screenshot confirm the panel renders correctly with zero QML warnings,
  but Logout/Reboot/Shutdown/Suspend/Hibernate were deliberately never
  fired — verify each by hand once. The confirm-dialog's click-outside path
  (does clicking outside the dialog cancel just the dialog, or the whole
  menu?) was checked by reading the z-order, not by driving a real pointer
  — worth a real click test.
- [ ] **Only then** remove `wlogout`, `configs/wlogout/`, its
  `configs/link.sh` entry, and the `install.sh` package line. Left alone
  for now.

**Acceptance — partial.** Panel renders and is keyboard/mouse navigable;
`Super+Shift+E` rebind needs a live reload to take effect; no action has
been fired for real yet; `wlogout` still installed and referenced.

---

## Phase 10 — System widget honesty · **M** — ✅ **DONE 2026-09-02**

**The widget had no panel at all** — just a bar label and a tooltip. So the
SPEC's entire hover list (CPU/GPU name, usage, memory, voltage, clock,
temperature, RAM/VRAM, battery, powermode toggle) was missing, which is
rather more than this phase's bullets implied. Built it.

- [x] **CPU and GPU names added** — `Intel(R) Core(TM) i7-8650U` with thread
  count, and `Kaby Lake-R GT2 [UHD Graphics 620]`, both read once at helper
  startup rather than re-derived per sample.
- [x] **Voltage → package power in watts.** Confirmed on this machine that
  `sensors -j` exposes exactly three voltage inputs — the battery (12.175 V)
  and two USB-PD rails (0 V, 5 V) — and no vcore anywhere. Package power via
  `/sys/class/powercap/intel-rapl:0/energy_uj` deltas is the substitute,
  emitted as a **nullable** field.
- [x] **The RAPL counter is root-only** (mode 0400), so a udev rule was
  needed: **`configs/powercap/`** with `99-powercap-readable.rules` and a
  `link.sh`, which `install.sh` picks up automatically via its
  `find -name link.sh` sweep. **Not yet applied — needs the owner's sudo.**
  Until it is, the panel says *"unavailable"* and explains why, rather than
  showing `0 W`.
  - The rule's own comment records *why* the counter is restricted
    (CVE-2020-8694 "PLATYPUS", a side-channel on high-frequency readers) and
    says plainly that deleting the rule is a supported choice — the panel
    already handles the counter being unreadable.
- [x] **VRAM: stated, not omitted.** The panel says *"Integrated GPU —
  shares system RAM, so it has no VRAM to report."* Reporting `0 MB` would
  be a lie rather than a missing reading.
- [x] **Both gated on a detected `gpuVendor`** (intel/amd/nvidia/unknown,
  parsed from `lspci`), so a discrete card would light these rows up with no
  code change.
- [x] **Stale comment corrected.** `system-stats.sh` claimed `intel_gpu_top`
  was not installed. It is (`/usr/sbin/intel_gpu_top`); the real blocker is
  `kernel.perf_event_paranoid=2`. The rc6-residency method stays correct and
  needs no privileges.
- [x] **One long-lived helper streaming JSON lines**, replacing a full
  respawn of the script every 5s (a fresh bash plus ~8 forks per sample,
  forever). Read with `SplitParser`, same shape as the cava and
  `nmcli monitor` readers, with a restart timer if it ever exits. Verified
  it is a child of quickshell, so `restart.sh`'s process-group kill reaps it.
- [x] **Powermode toggle surfaced in the panel** per SPEC — three buttons
  driving `toggles/toggle-powermode.sh` (TLP), with the current mode
  highlighted from its `get`.

**A QML trap worth remembering:** inside an inline `component`, child
elements are direct children of the component root, so `parent.parent`
reaches *past* it and yields undefined — logged as "Unable to assign
[undefined] to QString" **every frame**. `Weather.qml`'s `Stat` component
uses `parent.parent` correctly because its Texts sit inside an extra `Row`.
Reference the component through its own `id` and the nesting stops
mattering.

**Acceptance — met.** The panel shows CPU name/usage/clock/temp, a RAM bar,
GPU name/usage/clock, and the powermode selector; the two hardware-impossible
readings are labelled as such with the reason.

## Phase 11 — Multi-monitor correctness · **S-M** — ◐ **MOSTLY DONE 2026-09-02**

Already largely right (`Variants` over `Quickshell.screens` in `Bar.qml`,
`Background.qml`, `Osd.qml`, `notifications/Service.qml`).

- [x] **Fixed `Osd.qml` popping on every monitor.** It was
  `visible: root.opened` on a `Variants` over every screen, so a volume or
  brightness OSD appeared on all outputs at once. Each window now also
  requires `onFocusedMonitor`, computed by bridging
  `Hyprland.monitorFor(screen)` against `Hyprland.focusedMonitor` — so
  "focused" means what the compositor thinks, not what Qt guesses.
  - `Variants` is deliberately kept rather than building one window on the
    focused screen: a `PanelWindow` that changes `screen` at runtime tears
    down and rebuilds its wayland surface, and toggling `visible` on
    pre-built surfaces avoids a flicker if focus moves mid-OSD.
  - Falls back to visible when Hyprland has not yet reported a focused
    monitor, so the OSD is never swallowed entirely.
- [x] **Real mouse-wheel delivery to Workspaces verified** — the last
  open item from the hover/scroll list. Driving an actual wheel event
  (`ydotool mousemove -w -- 0 ±1`) over the widget switched workspaces and
  switched back. Previously only verified via IPC.
- [x] Live hover-transit with a real pointer — done in Phase 2a.

### A latent bug this uncovered: `osd show` could never be called

While testing the OSD, `quickshell ipc call osd show '{...}'` failed with
*"show: The following argument was not expected"* — for **any** argument,
including a bare string.

**`show` is one of `quickshell ipc`'s own subcommands** (it lists every IPC
target), so an `IpcHandler` function named `show` cannot be invoked from the
CLI with arguments at all: the parser binds `show` as a command and rejects
the payload. `call osd close` works fine, which is exactly why this hid —
and it means **`AppLibrary.qml`'s launch OSD had never actually fired**, nor
had anything else using the documented `call osd show '{…}'` contract.

Renamed to `present(payloadJson)`, with `show()` kept as a no-argument
alias. `AppLibrary.qml` updated. Verified: `call osd present '{…}'` returns
`ok` and the card renders.

### Still open

- [ ] **Hot-plug verification.** Cannot be done here — this machine has one
  output (`eDP-1`). The `Osd.qml` fix and `Background.qml`'s `Variants` both
  need a second display to confirm, as does deciding whether
  `scripts/watch-monitors.sh` is finally redundant (Phase 8).
- [ ] **Per-monitor widget sets** — one layout for all screens today. Left
  alone: it is a "consider", and there is no second monitor to design
  against.

## Phase 12 — "Any other REALLY cool things?" · ◐ **PARTLY DONE 2026-09-03**

- [x] **`toggles/toggle-nightlight.sh`** — and it turned out to be a repair,
  not just a feature. `hyprsunset` was installed and bound to
  SHIFT+brightness for raw gamma nudges, but **nothing ever started the
  daemon**, so both binds had been failing silently
  (`Couldn't connect to ….hyprsunset.sock`) for as long as they existed.
  - The daemon is now autostarted neutral (6000K), which fixes those binds
    as a side effect and gives the toggle something to talk to.
  - **`--gamma_max 150`**, because hyprsunset's default ceiling is 100 —
    which is also its starting value, so `gamma +5` could never do anything
    at all and only the *Down* half of that pair ever worked. Verified both
    directions after raising it.
  - `off` returns the temperature to neutral rather than killing the daemon:
    killing it would re-break the gamma binds, and an idle hyprsunset costs
    nothing.
  - Also takes `set <kelvin>` and `temperature`.
- [x] **Focus-mode scene** (`toggles/toggle-focus.sh`) — composes DND +
  keep-awake + night light through the existing toggles, with no logic of
  its own.
  - **Restores what it found** instead of turning everything off on exit,
    so a night light you had on for your own reasons survives a focus
    session. Verified both ways. The previous state is recorded in
    `$XDG_RUNTIME_DIR` (volatile) so a reboot mid-focus cannot leave a stale
    restore list.
  - Deliberately does **not** touch the network (offline mode is a far
    bigger hammer and most focus work still needs the internet) or the power
    mode (battery and AC sessions want opposite things, and it cannot tell
    which you meant).
- [x] **Animated pywal transitions** — done as part of the Phase 8 work.
- [x] **Colour picker** — already bound: `Super+P` runs
  `hyprpicker | wl-copy`. The roadmap's own recommendation was "just shell
  out to hyprpicker"; nothing to build.

### Still open

- [ ] **Workspace overview / alt-tab with live thumbnails** — the big one
  (**L**), built on `ScreencopyView` + Hyprland IPC. Untouched.
- [ ] **Screenshot with annotation** — blocked on tooling: `satty`,
  `swappy` and every other annotator are **not installed**, so there is
  nothing to shell out to. Needs a package decision first. `grim`/`slurp`
  are present and `Super+Shift+S` already captures to the clipboard.
- [ ] Bar auto-hide/reveal, per-app notification rules, bluetooth device
  battery (the last wants the native `Quickshell.Bluetooth` bindings
  deferred in Phase 1).

## Phase 13 — Surfaces the desktop sweep turned up · ✅ **DONE 2026-09-03**

### 13a. Clipboard — copyq retired · ✅

**The duplication was real and verified, not inferred.** A single probe
string copied once landed in **both** histories: quickshell's plugin went
121→122 entries and contained it, and `copyq read 0` returned it too. Two
managers were storing every copy you made.

- [x] **Determined which was serving: both were.** copyq ran 2 processes
  (`copyq -s` + `monitorClipboard`); the plugin ran 2 `wl-paste --watch`
  capture processes. A *third* watcher turned out to belong to `elephant`
  (walker's backend), so it goes away with walker.
- [x] **Decision: retire copyq.** The roadmap hedged on this, reasoning that
  copyq had "persistent storage across reboots" the plugin lacked. **That is
  wrong** — the plugin persists to
  `~/.local/state/quickshell/clipboard-history.json` (500-entry limit, 62KB
  and 121 entries at the time of checking) and *additionally* skips
  password-manager content (`CLIPBOARD_STATE=sensitive` /
  `x-kde-passwordManagerHint`), which copyq does not do here. With the one
  stated reason to keep copyq removed, retiring it matches every other
  replacement in this project. copyq's config was never tracked either.
- [x] **Bound `Super+Shift+V`** to `clipboard toggle`. The plugin had existed
  since port Phase 5 with **no keybind at all** — which is the whole reason
  copyq stayed in use and the two silently double-captured for months.
  `Super+V` was taken (`togglesplit`).
- [x] Removed from `hyprland_autostart.lua` and `install.sh`, and the running
  server stopped.

**copyq's data is deliberately untouched** (34 files, 200 items). The package
is still installed, so `copyq` by hand still opens the old history. Reversal
is one autostart line.

### 13b. Media / volume / brightness keys · ✅

- [x] **Routed through `scripts/media-key.sh`**, so the OSD is driven by the
  same action that makes the change instead of the shell inferring it
  second-hand. **Verified with real key presses** (`XF86AudioLowerVolume`):
  volume changes *and* the OSD appears with the correct bar.
- [x] **Fixed the hardcoded-sink bug.** The binds were
  `pactl set-sink-volume 0` — an index, not the default sink. On this machine
  the only sink is index **58**; `0` resolved purely because there is exactly
  one. Plug in Bluetooth or HDMI audio and the keys start adjusting the wrong
  device. Now `@DEFAULT_SINK@`.
- [x] **Dual-binding preserved without a second bind:** the script performs
  the raw action *first* and only then attempts the OSD, with the IPC call
  failure-tolerant. A dead shell costs you the popup, never the keys.
- [x] Added a missing **`XF86AudioMicMute`** bind — there was none.
- [x] Volume-up now unmutes, volume is clamped at 100% (pactl will happily
  clip past it), and brightness is floored at 1% (`5%-` can otherwise reach
  0 and leave a black screen).

**Two contract traps found in the OSD while wiring this:**

1. **The progress bar only renders when the message is EMPTY.**
   `OsdModel.stateForShow` sets `hasProgress` only if a value is present
   *and* `rawMessage === ""`, then renders the percentage as the message
   itself. Sending both a message and a value silently yields a text-only
   OSD with no bar — which is exactly what the first version of the script
   did.
2. **`iconFor()` takes semantic NAMES** (`volume`, `volume-muted`,
   `brightness`, `microphone-muted`, …) and owns the glyph mapping itself.
   The script speaks that vocabulary rather than passing raw glyphs, so the
   icon set stays defined in one place.

### 13c. Screenshot · unchanged

Still `grim -g "$(slurp)" - | wl-copy`. Annotation remains blocked on no
annotator being installed — see Phase 12.

## Explicitly out of scope

- **CPU/GPU voltage and VRAM** — physically unavailable on this hardware
  (Phase 10). Not a backlog item; a hardware fact.
- **Mobile broadband** — no WWAN modem exists (`mmcli -L` confirms).
- **LocalSend deep integration** — it has no CLI or headless mode; `--version`
  launches the full GUI. Use `kdeconnect-cli --share` for actual sends and
  treat LocalSend as a launch/status button, matching the existing Portmaster
  pattern.
- **A `shell.toml` theme-override layer** — deliberately omitted; this repo
  has one pywal-fed theme. Not a fidelity gap.
- **A compiled C++ Quickshell plugin** — rejected for the visualizer and by
  extension generally, at this repo's scale.
- **Porting polkit** — `polkit-kde-authentication-agent-1` is running and
  deliberately configured. Porting to `Quickshell.Services.Polkit` is a
  theming win only; rank it as such if ever picked up.
- **Costs widget** (GCP/Hetzner/Cloudflare) — scaffolded but non-functional;
  it needs credentials that do not exist anywhere, and Cloudflare's billing
  API requires an Enterprise plan. Dropped from the bar 2026-09-01; the
  owner's standing call is "not pursuing further for now". `Costs.qml` and
  `costs-fetch.sh` stay on disk if that ever changes.

---

## Beyond quickshell — desktop components this plan does *not* cover

A sweep of the running session (2026-09-01) found desktop-experience pieces
that quickshell **cannot** replace, because they are D-Bus API surfaces,
system services, or other apps' theming. They are recorded here so "the
quickshell roadmap" is not mistaken for "the whole desktop is handled".
None are blockers for any phase above; each is its own small piece of work.

- **XDG desktop portals — ✅ RESOLVED 2026-09-01.** Five backends were
  installed with nothing pinning the choice; backends compete to answer the
  same D-Bus interfaces and the winner depended on startup order. Not
  theoretical here — Flatpak is installed with real apps, and sandboxed apps
  reach the host *only* through portals. Fixed by:
  - `configs/xdg/hyprland-portals.conf` (symlinked by `configs/xdg/link.sh`
    to `~/.config/xdg-desktop-portal/`), pinning `default=hyprland;kde` —
    hyprland owns Screenshot/ScreenCast/GlobalShortcuts/InputCapture (the
    only backend that can see this compositor), everything else falls
    through to kde (FileChooser, AppChooser, Print, Settings, …).
  - Two interfaces neither implements, named explicitly:
    `Secret=gnome-keyring` (owned by the `gnome-keyring` package, so it
    survived the GNOME removal) and `Notification=plasmanotify`.
  - `xdg-desktop-portal-gnome` removed, which cascaded to `gnome-session`,
    `gnome-shell`, `gdm`, `gnome-control-center` — all unused session
    components (gdm was disabled, gnome-shell never running). No apps lost.
  - Note `kde.portal` declares `UseIn=KDE` while we run as Hyprland: since
    xdg-desktop-portal 1.18, `portals.conf` supersedes `UseIn` (this machine
    is 1.22.1), so naming the backend is sufficient.
  - Verified from the portal's own debug output: *"Using portal
    configuration file …/hyprland-portals.conf for desktop 'hyprland'"*,
    with both explicit preferences registered.
  - [ ] Remaining: confirm a Flatpak app's portal notification renders in
    the quickshell style (the `plasmanotify` line is the thing to revisit if
    not), and that a Flatpak file picker opens the KDE dialog.
- **Qt application theming — ✅ ROOT-CAUSED, partly fixed 2026-09-01.**
  `configs/uwsm/env` exported `QT_QPA_PLATFORMTHEME=qt5ct` — **but `qt5ct`
  was never installed.** Qt named a platform-theme plugin that did not exist
  and silently fell back to its built-in default, so *every* Qt app
  (qutebrowser, obs, proton-vpn-qt-app) was completely unthemed while GTK
  apps followed pywal. Changed to `kde`, which resolves to
  `KDEPlasmaPlatformTheme6.so` from `plasma-integration` (already
  installed) and reads `~/.config/kdeglobals` — already symlinked to
  `configs/plasma/kdeglobals`, which already carries full `[Colors:*]`
  blocks. **Takes effect on next login** (uwsm env).
  - ✅ **Qt colours now regenerate on every wallpaper change.**
    `scripts/generate-kde-theme.sh` writes all seven `[Colors:*]` groups plus
    `General/ColorScheme` + `AccentColor` from `~/.cache/wal/colors.json`,
    and is called from `switch-wallpaper.sh`'s `set_wallpaper()` alongside
    the other theme generators. Two deliberate choices in it:
    - **Semantic colours stay fixed** (`ForegroundNegative/Neutral/Positive`
      = KDE's red/orange/green). A first version derived them from the
      palette, which on a brown wallpaper made error text brown and success
      text orange — destroying the only information those colours carry.
    - **`ForegroundInactive` uses color8, not color7.** pywal frequently
      sets color7 equal to the foreground (it does on this palette), which
      rendered inactive text identically to normal text.
    - It uses `kwriteconfig6`, not `sed -i`: `~/.config/kdeglobals` and the
      Plasma appletsrc are *file* symlinks into the repo, and `sed -i` would
      replace the file and destroy the link. Verified kwriteconfig6 writes
      through the symlink and leaves it intact.
  - ✅ **Plasma's own wallpaper follows too.** The same script writes
    `Image=` into every `[Containments][N][Wallpaper][org.kde.image][General]`
    group in `plasma-org.kde.plasma.desktop-appletsrc` (one per screen /
    activity — setting only the first leaves other outputs stale), so a
    Plasma session started later comes up matching. It also calls
    `plasma-apply-wallpaperimage` when plasmashell is actually running,
    which under Hyprland it normally is not.
  - Alternative if the KDE look is ever unwanted: `QT_QPA_PLATFORMTHEME=gtk3`
    (`libqgtk3.so`, also installed) makes Qt follow the GTK theme, which is
    already pywal-driven — no generator needed, at the cost of GTK-styled
    Qt apps.
- **Printing — stack installed and running, but no printer configured.**
  `cups` and `avahi-daemon` are both **enabled and active**, `cups-filters`,
  `system-config-printer`, `print-manager` and `sane` are installed. But
  `lpstat -p -d` reports **"No destinations added"** — no printer has ever
  been set up — and two pieces are missing:
  - ✅ **`nss-mdns` installed and wired.** `/etc/nsswitch.conf`'s `hosts:`
    line is now `mymachines mdns_minimal [NOTFOUND=return] resolve
    [!UNAVAIL=return] files myhostname dns` — `mdns_minimal` must precede
    `resolve`, and `[NOTFOUND=return]` keeps ordinary lookups falling
    through to DNS. Backed up to `/etc/nsswitch.conf.bak-<date>` first, and
    localhost/public-DNS/ping were re-verified immediately after, since a
    bad `hosts:` line breaks *all* name resolution.
  - ✅ **`cups-pdf` installed and its queue created.** The package ships the
    backend and PPD but does **not** create the queue, so it alone would
    still have left zero printers. `lpadmin -p PDF -v cups-pdf:/ -m
    CUPS-PDF_opt.ppd -E` + `lpadmin -d PDF` creates and defaults it;
    verified end to end by printing a test job that produced a real PDF in
    `/var/spool/cups-pdf/luca/`. (`lpadmin` warns that PPD-based drivers are
    deprecated in future CUPS — worth revisiting eventually.)
  - ✅ All of the above is reproducible: `nss-mdns`, `cups-pdf` and
    `plasma-integration` are in `install.sh`'s package list, and a new
    `## PRINTING` section there enables `cups`/`avahi-daemon`, applies the
    nsswitch edit idempotently (only if `mdns_minimal` is absent), and
    creates the PDF queue only if it does not already exist.
  - No printer is currently on the network or attached via USB
    (`lpinfo`/`avahi-browse` find nothing), so none of this can be verified
    end-to-end right now.
  - Printing reaches Flatpak apps through the **`Print` portal**, which the
    portal work above now routes to KDE — so `print-manager` is the dialog
    those apps will get.
- **Secrets / keyring.** `gnome-keyring-daemon` runs with
  `--components=pkcs11,secrets`, and `kwallet` + `kwallet-pam` are also
  installed. Same duplication smell as the portals. Not quickshell's job,
  but worth deciding which one owns Secret Service.
- **Display manager.** `gdm`, `ly`, and `sddm` are all installed; none is
  enabled (login is via TTY + uwsm). Quickshell *does* ship
  `Quickshell.Services.Greetd`, so a pywal-themed greeter matching the lock
  screen is genuinely possible — an ambitious but real "full DE" item. Left
  out of the phases above because it was never requested; raise it if
  wanted. Meanwhile, three unused DM packages are worth pruning.
- **`hyprpm` plugins.** `hyprland_autostart.lua:9` runs `hyprpm reload`.
  Hyprland's own plugin layer, out of scope by the "apart from Hyprland"
  boundary, but it is a moving part that can break the session on a
  Hyprland upgrade.
- **`xhost + local:` / `xhost +SI:localuser:root`**
  (`hyprland_autostart.lua:10-11`) disables X11 access control for local
  users so XWayland/root GUI apps work. It is a standing security loosening
  unrelated to quickshell — flagged, not judged.

---

## Open decisions

- **Offline mode and Bluetooth input** — should `toggle-offline.sh` exempt
  paired BT input devices? None are paired today, so the default is "disable
  everything". Revisit if a BT keyboard/mouse is added (Phase 1).
- **"Windy" threshold** for the 3-day summary (Phase 4).
- **Hourly window** — rolling 24h is recommended and assumed; calendar-day
  framing is the alternative (Phase 4).
- **`toggles/` vs a `settings/` sibling** for value-carrying settings (font,
  scale, wallpaper). Recommendation is to keep them in `toggles/` with the
  `list`/`set` actions; see `02 §3`.

---

## Suggested order if you want visible progress fast

Phase 0 (safety) → Phase 1 (the SPEC's explicit "not hacked together" ask) →
**Phase 8's `Behavior on color`** and **Phase 12's nightlight toggle** as
cheap visible wins → Phase 2a → Phase 3 (media, the headline gap) → Phase 4
(weather) → the rest by appetite.


---

## Appendix A — permanent facts about this codebase

Carried over from TODO.md when quickshell work consolidated here. These are
things that have already cost debugging time at least once.

- **One deliberate deviation from upstream omarchy-shell**: hover-driven
  panel-open (`Bar.qml` / `Ui/HoverPanel.qml`, `hoverCloseTimer` grace
  period) instead of upstream's click-to-toggle. Built to explicit earlier
  feedback and re-confirmed by the SPEC. Every widget's trigger wiring is
  `bar.hoverOpen(moduleName)` / `bar.hoverTriggerExit(moduleName)`, never
  `panel.toggle()`.
- **No `shell.toml` theme-override layer, on purpose.**
  `Commons/Color.qml` / `Style.qml` / `Border.qml` deliberately lack it —
  one pywal-fed theme, not swappable themes. **Do not port it back**; it is
  not a fidelity gap. Where upstream code calls into it (`Border.surfaceSpec`
  etc.), the established adaptation is `Border.flat(color, width)`.
  `Util.editsFilter`/`editedFilter` likewise has no local equivalent; the
  substitute is explicit `Key_Backspace` + printable-character handling.
- **`shell` is a reserved-ish name.** A property named `shell` on `Bar.qml`
  (or on any object declared inside `shell.qml`'s own construction blocks)
  shadows the outer `ShellRoot`'s `id: shell` and silently breaks injected
  properties. **This has regressed twice.** Use `shellHost` for that kind of
  reference. Services loaded via `shell.qml`'s `ensureService()` /
  `_syncServices()` loader are a different, safe context — that assignment is
  imperative JS, not a declarative binding.
- **`bar.foreground` does not exist; it is `bar.barForeground`**
  (`Bar.qml:50`). Three occurrences so far. Check this before adding any new
  `bar.*` color read.
- **`restart.sh` used to orphan five helper processes per restart.** Fixed
  2026-09-02. Several widgets own long-lived children — `wl-paste --watch`
  x2 (clipboard), `inotifywait -m` (plugin registry), and `nmcli monitor`
  (network, added in Phase 1) — and **quickshell does not reap them on exit,
  on SIGTERM or SIGKILL** (both tested). The old `pkill -9 -f "^quickshell
  -p"` therefore left one of each behind on every restart, reparented to the
  user manager and invisible to the next `pkill`. Three stray `inotifywait`
  processes accumulated from three restarts in one session before this was
  spotted. Children inherit quickshell's PGID, so `restart.sh` now kills the
  process *group* (guarding against signalling its own group). Verified flat
  process counts across three consecutive restarts.
  - Corollary for debugging: `pgrep -f 'nmcli monitor'` **matches its own
    shell's command line** and will report phantom survivors. Count with
    `pgrep -cx nmcli`.
- **`mapToItem` is not reactive, and reading it inline is not enough
  either.** QML does not track the ancestor positions it walks, so a binding
  on it evaluates once and goes stale; and the signals that tell you the
  layout changed fire *during* the layout pass, when the chain is
  half-settled. Both halves have to be handled: recompute imperatively, and
  defer the recompute by a frame. See `BarWidget.barX`.
- **A top-anchored layer surface already clears the bar.** `Bar.qml` sets
  `exclusiveZone = barSize`, so `margins.top` is measured from *below* the
  bar. Writing `barSize + 4` double-counts it — that is what put every panel
  30px too low until 2026-09-02.
- **`hyprctl dispatch` takes Lua here, not the classic string form.** This
  repo drives Hyprland from `.lua` configs, so `hyprctl dispatch movecursor
  649 15` fails with a Lua parse error and **`hyprctl dispatch workspace 2`
  silently does nothing** — which invalidated one test in this session
  before it was noticed. The working form is
  `hyprctl dispatch 'hl.dsp.cursor.move{x=649,y=15}'`; grep
  `hyprland_keybindings.lua` for `hl.dsp.` to find the right dispatcher name.
- **Simulating a pointer: warp for position, `ydotool` for motion.**
  `hyprctl dispatch cursor.move` places the cursor exactly but sends **no
  motion event to a client already under it**, so hover never updates and
  panels look frozen on the first widget hovered. `ydotool mousemove -a` is
  skewed by pointer acceleration. Warp to the start point, then drive
  `ydotool mousemove -x ±1` for the actual movement. `ydotoold` must be
  running first (its user unit is inactive by default).
- **`hyprctl keyword` is a no-op here, and exits 0.** This repo's Hyprland
  config is Lua, and against a non-legacy parser `hyprctl keyword` prints
  "keyword can't work with non-legacy parsers. Use eval." and **returns
  success**. Anything built on it silently does nothing. Use
  `hyprctl eval '<lua>'` — e.g.
  `hyprctl eval 'hl.monitor({output="eDP-1", mode="1920x1080@60", position="0x0", scale=1.25})'`.
- **`cmd | grep -q x` fails under `set -o pipefail` when it MATCHES.**
  `grep -q` exits on the first hit, the upstream command dies of SIGPIPE,
  and pipefail propagates that as failure. Read into a variable and grep the
  variable. Cost a "font is not installed" rejection for fonts that were.
- **`Ui/HoverPanel.qml` sets `keyboardFocus: None` by default**, so a text
  field inside a hover panel silently swallows every keystroke. Set
  `acceptsKeyboard: true` on the panel (opt-in, added for the font search).
- **An overlay plugin's `close()` must not call `shell.hide()`.**
  `shell.hide()` invokes the plugin's own `close()`, so the pair recurses
  until the stack blows. The failure is *delayed and misleading*: the
  shell's `openPanelIds` entry is never cleared, so every later `summon`
  returns "ok" and delivers nothing — an overlay that works exactly once and
  then appears to have a broken IPC. Split `close()` (shell-invoked) from
  `dismiss()` (plugin-invoked, closes and notifies the shell), as
  `ReminderFlow.qml` and `plugins/alert/Alert.qml` both do.
- **`Keys.onX` cannot attach to a `PanelWindow`** — it is a wayland surface
  interface, not an Item. It logs "Could not attach Keys property to … is
  not an Item" and then silently never fires. Wrap the content in an Item
  (`Ui/PanelKeyCatcher.qml` exists for this).
- **`systemd-run --user` timers need `--timer-property=AccuracySec=1s`.**
  The default accuracy is one minute and systemd coalesces wakeups:
  measured, a 5s timer fired 10s late. Fine for a reminder, not for a
  countdown a user is watching.
- **A self-chaining transient unit must use a fresh unit name each time.**
  If the firing unit and the next one share a name, cancelling "the old
  timer" from inside the firing unit kills the unit that is running the
  cancel. Stop only `*.timer` units, never `*.service`, when the caller may
  itself be that service.
- **Never declare `property var data` on an Item-derived type.** `data` is
  Item's *default property* — the list its child objects are assigned into —
  so declaring one shadows it and the type's visual children are silently
  never added. Cost real time in Phase 4: the symptom was that the weather
  hover panel worked perfectly (a `PanelWindow` is its own window, so it
  survived) while the bar trigger rendered nothing **and still occupied
  layout space**, which looks like a paint or color bug, not a property
  collision. The same applies to `children` and `resources`.
- **`pkill -f <pattern>` matches its own wrapper shell.** `pkill -f
  fake_mpris.py` killed the very shell running the command (exit 144) —
  because that shell's command line contains the pattern. The same trap
  makes `pgrep -cf 'nmcli monitor'` report phantom processes. Use
  `pgrep -x <name>`, or the bracket trick (`'fake[_]mpris'`), and kill by
  PID.
- **`grim` screenshot verification is unreliable here** — sometimes real
  content, sometimes near-black noise, never root-caused. Confirm with a
  second capture before trusting a "broken" result.
- **Upstream reference**: `git clone --depth 1
  https://github.com/basecamp/omarchy.git` into a scratchpad when resuming
  port work. Not vendored into this repo.
- See also the numbered Ground rules at the top of this file, which cover
  `keepLoaded`, the live-layout state file, `restart.sh`, glyph cmap
  verification, and the toggle contract.

---

## Appendix B — port history (condensed)

The full 1:1 port from Omarchy's `shell/` completed in 8 phases before this
roadmap began. Per-file provenance is in `THIRD_PARTY_NOTICES.md`; each
file's own header comment carries its adaptation reasoning. One line each,
kept because the *bugs found* are the reusable part:

- **Phase 1** — the 16 base-layer `Ui/` atoms. Real gap: `Border.qml`'s
  theme-override call sites, adapted to the plain fallback.
- **Phase 2** — the plugin-registry / `shell.qml` / `Bar.qml` cutover, the
  highest-risk phase, done live and backed up first. 4 bugs found: missing
  `Util.qml` helpers, the `shell`-shadowing bug, the rescan script needing
  `-L` for this repo's symlink layout, and a missing `services/` `link.sh`
  entry. Also fixed a ~85-90%-of-a-core respawn bug in `AppLibrary.qml`
  (`hiddenEntryScan` unthrottled on a repeatedly-firing signal).
- **Phase 3** — `Spacer`, `Tray`, `KeyboardLayout`, `SystemUpdate`,
  `Indicators` (Dnd + StayAwake only — the others have no backing tool
  here). 3 bugs: the `shell`-shadowing bug's second occurrence, a
  `bar.foreground`/`barForeground` mismatch (first occurrence), and
  `BarIndicator` setting properties this repo's `WidgetButton` never had.
- **Phase 4** — `Battery.qml` on `Quickshell.Services.UPower` +
  `toggle-powermode.sh` (TLP) rather than upstream's
  power-profiles-daemon approach.
- **Phase 5** — replaced mako with the native notification daemon, replaced
  walker with the native launcher (`plugins/appsearch/`, a purpose-built
  picker rather than a port of upstream's larger command-menu engine), and
  upgraded `Clipboard.qml`. Polkit deliberately kept as the existing KDE
  agent. All three replacement decisions were the owner's explicit call.
  *(Both "replacements" turned out to be incomplete — see Already-done for
  mako's D-Bus activation, and Phase 7 for walker's `Super+D` binding.)*
- **Phase 6** — `speedtest`/`disk-speedtest`, `wifiqr`, `emojis`,
  `image-picker` (standalone, never wired — Phase 8), `reminders` (Phase 5
  of this roadmap). `dropbox`/`tailscale`/`dev-gallery` skipped. The
  `keepLoaded` rule was discovered here.
- **Phase 7** — the lock screen's visuals onto the existing PAM /
  `WlSessionLock` backend, verified via a throwaway non-locking preview.
- **Phase 8** — final pass: clean restart, a scripted glyph-cmap sweep
  (caught one bad codepoint), full IPC smoke tests, rewrote
  `THIRD_PARTY_NOTICES.md`. Fixed two NUL-byte file-corruption bugs from a
  tool quirk where a literal 4-hex-digit Unicode escape typed as prose gets
  decoded into a real NUL.
- **Post-Phase-8** — relaxed four aggressive poll timers to
  per-widget-appropriate intervals (5-20s). `FileView` push updates were
  considered and rejected: `StayAwake`'s "is the inhibit process alive"
  check has no corresponding file-write event to push off. Added
  Workspaces scroll-to-switch (real wheel delivery still unverified —
  Phase 11).
