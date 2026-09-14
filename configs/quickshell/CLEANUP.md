# Quickshell cleanup pass — 2026-09-14

Goal: make the shell coherent, fix real bugs, remove dead weight, and make
the widget/plugin plumbing future-proof. Feature scope is unchanged — see
`research/ROADMAP.md` for the plan and its permanent gotchas.

Status legend: `[ ]` todo · `[x]` done · `[-]` out of scope, flagged

## A. Audit

- [x] A1 — Survey the tree (163 files, ~20k lines QML/JS), read `ROADMAP.md`'s
  ground rules and Appendix A gotchas.
- [x] A2 — Read the *running* shell's own log rather than only its source.
  That is what turned up B6, B7 and B8; none were visible by reading.

## B. Bugs fixed

- [x] B1 — `bar.spacer` was unreachable. `Spacer.manifest.json` + `Spacer.qml`
  existed but `BarSection.qml`'s id→file map had no entry, so a layout naming
  it rendered nothing at all. Added; unresolved ids now warn instead of
  silently drawing nothing.
- [x] B2 — `bar.exit` had no manifest, so the plugin registry did not know the
  widget existed — it could not be listed, enabled or placed over IPC. Added
  `Exit.manifest.json`.
- [x] B3 — The live `~/.local/state/quickshell/shell.json` was missing
  `bar.exit`, so the running bar and `builtinShellConfig` disagreed (ground
  rule #5).
- [x] B4 — Removed the debug `console.log` that fired for every widget on
  every bar load (`BarSection.qml`).
- [x] B5 — The Wi-Fi password field could never receive a keystroke.
  `HoverPanel` defaults to `WlrKeyboardFocus.None` and Network's panel never
  set `acceptsKeyboard`, so a secured network could not be joined from the
  bar at all.
- [x] B6 — `Exit.qml` was inert *and* invisible. It used `onClicked`, which
  `WidgetButton` does not declare (logged "Cannot assign to non-existent
  property" on every load); it declared no `implicitWidth`/`implicitHeight`,
  so `BarSection` sized it to zero; and it never passed `bar` down to its
  button. Its `moduleName` also carried the `bar.` layout prefix, unlike
  every other widget.
- [x] B7 — `BarSection`'s load-failure handler called `errorString()` on the
  Loader, which does not have it, so the handler meant to name a broken
  widget threw `ReferenceError` instead. Reads it off `sourceComponent` now.
- [x] B8 — `ImagePicker.qml`'s three `Keys.on*` handlers used the injected
  `event` parameter, deprecated in Qt 6 and warned about on every load.
  Converted to `function (event)` form.
- [x] B9 — `AppLibrary`'s icon scan joined `XDG_DATA_DIRS` entries without
  trimming a trailing slash, indexing icons under `/usr/share//icons`.
- [x] B10 — Clicking an output/input device in the audio panel re-read the
  device list *inline*, racing the detached `pactl` that had not applied yet,
  so the selection did not move and the click looked ignored. Same class of
  bug in Network's six toggles, where `Qt.callLater(refreshAll)` re-read the
  `get` scripts on the next frame — always before the toggle had run. Both
  now re-read on a settle delay.
- [x] B11 — The clock's calendar grid was bound to `calendarWeeks()`, which
  reads `now`, so all 42 delegates were rebuilt once a second for as long as
  the panel stayed open. Rebuilt on a day-resolution key instead.
- [x] B12 — The weather sparkline only repainted on `Color.accent` changes,
  leaving the temperature line, both axes and every label on the previous
  wallpaper's palette. Watches `foreground` too.
- [x] B13 — The audio panel's input-device list sat *below* the deafen row and
  a separator, one section past the MICROPHONE header it belongs to, reading
  as a third unlabelled list. Moved under its own header; deafen, which spans
  both sections, now goes last.

## C. Future-proofing

- [x] C1 — `BarSection.qml` duplicated every manifest's `entryPoints.barWidget`
  in a hardcoded map, so no third-party `bar-widget` plugin could ever render:
  its .qml lives in the user plugin directory, which that file cannot know
  about. It now resolves through the plugin registry first and keeps the map
  purely as the cold-boot fallback, re-resolving when the async scan lands.
- [x] C2 — 23 call sites across 17 files hardcoded
  `$HOME/projects/arch-dotfiles/...`, baking both the checkout location and
  the repo's internal layout into widget code. Replaced with a
  `Commons/Paths.qml` singleton: `shellDir`-relative for anything shipping
  inside the shell, plus one `QS_DOTFILES_DIR`-overridable root for
  `toggles/`, repo `scripts/`, `wallpapers/` and `themes/`. The two shell
  scripts that hardcoded the same path honour the same variable.
- [x] C3 — Four hand-written `quickshell ipc -p ...` argv arrays replaced with
  `Paths.ipcCall()`, so the `-p` argument cannot drift per call site.
- [x] C4 — `Ui/ScreenMoveRemap.qml` was ported and then never wired to
  anything. It is the fix for Hyprland leaving a mapped layer surface at its
  old global position when its monitor moves — i.e. undocking leaves the bar
  and the wallpaper drawing at the previous origin. Both now fold it into
  their `visible` binding. Verifiable only on a second display (see
  ROADMAP Phase 11's open hot-plug item).

## D. Coherence

- [x] D1 — Retargeted stale `TODO.md` references in 9 QML files and
  `THIRD_PARTY_NOTICES.md`; that file was folded into `research/ROADMAP.md`.
- [x] D2 — `pywal` → `wallust` across 11 comments. Wallust replaced pywal on
  2026-09-03 and deliberately writes pywal's paths, so `~/.cache/wal/` stays —
  `Commons/Color.qml` now says why instead of leaving it looking like drift.
- [x] D3 — Deleted three `Ui/` atoms with no call site anywhere:
  `MultiSelect.qml` (623 lines), `NumberField.qml`, `PanelHero.qml`. Ported
  but never used, so never exercised; recoverable from git if a later panel
  wants them. `ScreenMoveRemap.qml` was in the same state and got wired
  instead (C4) — it was a latent bug, not dead code.
- [x] D4 — `shell.qml` now states which of the shell's two component
  mechanisms to use for what: always-on instances declared in that file, vs.
  manifest-driven plugins discovered by `PluginRegistry`. The split was
  deliberate but undocumented, so it read as drift.

## E. Verification

- [x] E1 — Restarted via `restart.sh`. The shell now starts with an entirely
  clean QML log; the previous run logged the Exit and `errorString` failures,
  the ImagePicker deprecation warnings, and per-widget debug spam.
- [x] E2 — Opened all 11 bar panels and the speed-test overlay over IPC: no
  warnings.
- [x] E3 — Helper-process hygiene across four restarts (Appendix A's
  orphaning bug): `inotifywait` 1, `nmcli` 1, `wl-paste` 2, one quickshell.

## F. SPEC gaps — all four closed

Found during the cleanup pass, built afterwards on request.

- [x] F1 — **OBS status widget.** `Obs.qml` + `obs-status.py`, a long-lived
  obs-websocket 5.x client (auth, event subscriptions, reconnect) read through
  a SplitParser. Bar shows LIVE / REC / LIVE+REC / RECONNECTING with a pulsing
  state dot and elapsed time; the panel carries scene, output FPS, frame render
  time, OBS CPU and memory, bitrate, bytes sent, dropped frames with
  percentage, congestion, recording size, disk free, and render-vs-encode
  skipped frames as separate rows.
  - Port and password are read from obs-websocket's **own** config file, so
    they exist in exactly one place and never in git. `configs/obs/link.sh`
    generates that file with a fresh random password if it is missing.
  - Bitrate is derived in the widget from successive byte counters, because
    obs-websocket reports cumulative session bytes, not a rate.
  - The helper starts only once an OBS window has been seen (ToplevelManager,
    event-driven — no polling, no `pgrep` fork), so its ~13 MB costs nothing
    on a day without OBS.
  - **Controls, not just a readout**: a scene switcher (chips in OBS's own
    list order, reversed back from the API's bottom-first ordering) and
    Go live / Stop, Record / Stop rec, Pause / Resume. Commands travel back
    down the helper's **stdin** as one JSON object per line — the reverse
    channel of the pipe the widget already reads — so a button press is a
    single request on the authenticated session rather than a fresh handshake
    and auth round trip per click. The allowed command set is one table in the
    helper; that is the only path from the desktop into OBS.
  - Both modes are first class: **recording gets its own bitrate**, derived
    from `recordBytes` separately from the stream's, because the local file is
    routinely encoded far heavier than what goes out — plus **disk headroom**
    ("126:03:54 at this rate"), which is what turns "325 GB free" into
    something actionable mid-session.
  - Verified end-to-end against a mock obs-websocket server (auth handshake,
    subscription mask, request/response id matching, event-driven re-poll,
    and both command types arriving with the right payload), then against the
    real client while it was recording: live scene list, 6009 kbps, disk
    headroom, and `SetCurrentProgramScene` accepted for a real scene and
    rejected for a bogus one.
  - Detection of "is OBS running" is by **process**, not by window. The
    obvious cheap answer is ToplevelManager — no fork, no timer. It does not
    work: measured with OBS open and recording, its only mapped toplevel was a
    CEF browser-source dialog whose appId and class are both the empty string,
    and the main window was in the tray with no toplevel at all. `pgrep -x obs`
    on shell start, on any toplevel change, and on a 60s fallback until found.
- [x] F2 — **Discord call widget.** `Discord.qml` reads a JSON file published
  by `configs/discord/plugins/QuickshellVoiceStatus.plugin.js`, a first-party
  BetterDiscord plugin. The bar shows participant avatars that **scale up and
  gain a green ring while speaking**, dim while silenced, with a mute or
  deafen badge on the avatar; the panel lists everyone with separate
  server-mute vs self-mute, deafen, video and screen-share indicators.
  - Discord's own RPC socket carries exactly these events and gates all of
    them behind an OAuth scope that requires an app registered by hand on
    Discord's developer portal — not something a dotfiles repo can ship. The
    BetterDiscord route needs no account setup and gives richer data.
  - **Needs BetterDiscord injected** (`betterdiscordctl status` currently says
    `Discord "index.js" injected: no`; `betterdiscordctl reinstall` fixes it).
    Until then the widget stays hidden, which is the correct degraded state.
  - State file lives in `XDG_RUNTIME_DIR`, written atomically, with a 15s
    heartbeat so the widget can tell a quiet call from a dead client.
- [x] F3 — **Weather alerts and radar.**
  - Alerts from MeteoAlarm's CAP feeds (~38 European countries; outside that
    footprint the panel says the region is unsupported rather than showing a
    silent nothing). Matching is two-tier: a real point-in-polygon test where
    the issuer publishes a polygon, a normalised area-name token match
    otherwise, reported as "your area" vs "your region" so the looser claim is
    not passed off as the tighter one. Green/level-1 is filtered out — the
    Dutch feed alone carried 493 warnings, all of them level 1.
  - **No free text crosses into the QML at all** — no headline, description or
    instruction. Warning prose names places constantly and there is no
    reliable scrub, so only structured fields are emitted. The bar shows a
    pulsing alert glyph for orange and red only.
  - Radar from RainViewer, fetched as **local PNG frames** rather than URLs:
    every radar URL carries the centre coordinate, so loading it from QML
    would reintroduce the location the weather pipeline exists to keep out.
    Twelve frames, two hours, play/pause and a scrub slider.
  - **No basemap, deliberately** — compositing radar over a street map would
    draw the user's own town in the panel. Labelled range rings at round
    distances (50/100/150 km here) plus a centre marker give scale instead.
- [x] F4 — **Keyboard-backlight OSD.** `scripts/media-key.sh` gained
  `kbd-backlight-up|down|toggle`, driven in raw steps because
  `tpacpi::kbd_backlight` has max_brightness 2 — `5%+` on a 0-2 device rounds
  to zero and the key does nothing. Toggle cycles off/dim/bright rather than
  flipping between extremes. The device is discovered, not hardcoded.
  `XF86KbdBrightnessUp`/`Down`/`KbdLightOnOff` and `SUPER+SHIFT+B` are bound;
  the chord is the guaranteed path because ThinkPads handle Fn+Space in
  firmware and may deliver no key event at all. Verified by cycling the device
  through all three levels.

## G. Bugs found while wiring the new widgets

- [x] G0 — **Tray right-click menus could never open.** Two bugs in the same
  block, in both the horizontal and vertical tray layouts:
  1. The "empty space right-click opens the manage popup" MouseArea was
     declared *after* `trayClip` and `anchors.fill: parent`, so it sat on top
     of every tray icon and swallowed each one's right-click before it reached
     the item's own MouseArea. `openTrayMenu()` was never called.
  2. That same handler was written `onPressed: function(button)`, but
     MouseArea's `pressed` carries a **MouseEvent**, not a button number — so
     `button === Qt.RightButton` was permanently false and the handler did
     nothing either. The press was still accepted, and therefore still
     swallowed.
  Declared first (below the icons in z-order) and given the right signature.
  Verified with a real synthetic right-click on the Discord tray icon: the
  app's own menu now opens.
- [x] G0b — `Ui/PopupCard.qml` called `bar.requestPopout()` /
  `bar.releasePopout()` in `onOpenChanged`. This repo's `Bar.qml` deliberately
  never ported upstream's popout coordinator, so every popup open threw a
  TypeError out of that handler. Guarded on the method existing rather than
  deleted, so a future bar that implements the contract still gets it.

## H. Bar layout — "behaves and looks nicely with more widgets"

The right-hand cluster had grown to twelve items in one undifferentiated run,
and two of them resized constantly.

- [x] H1 — **The bar no longer twitches.** `System.qml` drew its stats as one
  long concatenated string, so CPU crossing 9%→10%, the clock dropping a digit,
  or the temperature ticking each changed the widget's `implicitWidth` and
  shoved every widget to its left along the bar. Each stat now has its own slot
  whose width is **measured from the widest value it can ever show** rather
  than guessed in pixels — a guessed width was already wrong once the CPU clock
  reached four digits, and the value overflowed left underneath its own glyph.
  Measuring also survives a `theme.json` font change. Network's speed readout
  got the same treatment; it was twitching in time with traffic.
- [x] H1b — **One spacing rhythm.** The gaps came from two places that did not
  agree: an icon widget is a 30px slot around a 16px glyph (7px a side), while
  a text widget padded itself with `controlPaddingX` (12px a side). With the
  section's own 6px between them, two text widgets sat 30px apart and two icon
  widgets 6px apart — on the same row, nominally evenly spaced. Now
  `Style.bar.itemPaddingX` (derived from the icon slot), `itemGap` and
  `groupGap` are the only three numbers, and one of them changes the density of
  the whole bar.
- [x] H1c — **Network throughput dropped from the bar.** It was the one number
  changing every second, it is rarely what you want at a glance, and the slot
  wide enough to stop it twitching cost ~120px of a bar that is now full. The
  panel still shows it, beside the device and IP it belongs with.
- [x] H1d — **Focused-workspace pill inset** off the bar's top and bottom
  edges. Edge to edge on a 30px bar it read as a block of background rather
  than a control sitting on the bar.
- [x] H2 — **Grouped, with hairline separators.** A new `bar.separator` widget,
  placed from the layout rather than hardcoded in `BarSection` — which widgets
  belong together is exactly the thing that changes as widgets are added, so it
  has to be a layout decision. Groups, outward from the centre: session-state
  (OBS, Discord, tray) · machine (system stats) · connectivity (network,
  display, audio) · attention (notifications, keyboard layout, indicators) ·
  session (power menu).
- [x] H2b — **Cut back to ONE separator**, between the widgets that come and go
  and the ones that are always there. Rules between permanent widgets were
  noise: they never divide anything that changes, so they add a line to look at
  for no information.
- [x] H2c — **Re-sectioned.** Time and weather moved to the LEFT beside the
  launcher and workspaces — reference information you glance at, not something
  that should own the middle of the screen. The centre is now what is happening
  right now: media and the Discord call. OBS sits left of the tray.
- [x] H3 — **Transient widgets go first in the cluster.** The section is
  right-aligned, so a widget appearing or vanishing at the left of it grows the
  cluster into empty space and every icon to its right keeps its position. OBS,
  Discord and the tray all come and go; anywhere else in the order and the
  permanent icons shuffle every time OBS opens.
- [x] H4 — **Separators hide when their group is empty.** Half these widgets
  hide themselves when they have nothing to say, and a separator whose whole
  group has vanished is a rule floating against the edge with nothing on one
  side — it reads as a rendering bug. A separator only draws with real content
  on both sides; neighbouring separators do not count, which also collapses a
  run of two rules when the group between them is empty.
- [x] H5 — **Discord avatars are round.** They were not: QtQuick's `clip` is a
  rectangular scissor test that ignores `radius`, so a rounded `Rectangle` with
  `clip: true` still clipped the image to a SQUARE, which is what made the
  chips look like pasted-on tiles with a ring around them. Swapped to
  `Quickshell.Widgets.ClippingRectangle`, which clips to the real rounded
  shape. Also: decode at 2× the drawn size with mipmapping (decoding a 64px
  avatar straight down to 20px threw away most of the pixels and left it
  blocky), ring moved *outside* the clipped circle so it is not a hard stroke
  on an already hard edge, and the mute/deafen badge given an opaque disc so it
  stays legible over any avatar.

- [x] H6 — **OBS label states verified, not assumed.** `LIVE+REC` / `LIVE` /
  `REC` / `OBS` all confirmed against the mock server by driving the two output
  flags through every combination. Streaming outranks recording in both the
  label and the colour, and the label itself is now tinted to the state — an
  8px dot was the only thing separating "live" from "recording" at a glance,
  which is not enough to carry that difference.

- [x] H7 — **Discord widget gained controls.** Mute and deafen, driven through
  a new command channel: the widget drops a single-line JSON file that the
  BetterDiscord plugin polls at 250ms and **unlinks as it reads**, so a command
  cannot be replayed. Polled rather than watched because Discord's renderer
  `fs` is a partial shim — `fs.watchFile` is undefined in it (probed). The
  accepted verbs are one short table in the plugin; that is the entire surface
  anything outside Discord has to drive the client. Round trip verified: both
  commands were consumed and the mute toggled and restored.
  - **No "go live" button, deliberately.** Probed this build for it: no
    `startStream`, no `openGoLiveModal`, no module carrying both start and stop
    stream, and no Go Live control findable in the DOM. Screen-sharing also
    needs a source picked, which is a modal of Discord's own. A button that
    silently did nothing would be worse than its absence.

- [x] H8 — **Radar overlay: wind vector field, isobars, compass.** A new
  `weather-field.sh` requests a 5x5 grid over exactly the square the radar
  covers. Open-Meteo takes a list of coordinates in ONE request (verified: it
  pairs `latitude[i]` with `longitude[i]`, so it is not a cross product and
  every grid point is sent explicitly), which makes a field a single call
  rather than 25.
  - `pressure_msl`, **not** `surface_pressure`. The first run over this grid
    spanned 936–1024 hPa purely from elevation — station pressure falls ~12 hPa
    per 100 m, so contouring it draws the terrain. Mean-sea-level pressure is
    the field isobars are defined on; the same grid then reads 1024–1026.
  - Same privacy contract as the rest of the weather pipeline: the response
    echoes a snapped lat/lon per point — 25 chances to pin the user — and none
    of it is forwarded. Each point becomes a (u, v) fraction of the radar
    square, asserted against the banned-key list before it is printed.
  - Arrows point where the wind is GOING (`dir` is the direction it comes
    from, so +180), length and opacity carry speed with a floor so a calm cell
    still shows a direction. Isobars are marching squares over a bilinear
    sample of the grid, sub-sampled 6x so the contours curve instead of
    stepping at every cell edge, at the standard 1 hPa interval — 4 hPa would
    give a single line over a 2 hPa spread. Compass bottom-left, because
    otherwise the arrows are a direction relative to nothing. One Canvas for
    all three: they share a coordinate space and a repaint trigger.
- [x] H9 — Radar said "Radar unavailable" while it was merely loading. A cold
  cache is twelve PNG downloads; that is the state a first open lands in every
  time. Now distinguishes loading from failed.

## H10. Full review pass

Ran after the layout work, over the whole shell rather than just the diff.

**Defects found and fixed**

- [x] **The centre section was never centred on the screen.** It sat between two
  `Layout.fillWidth` spacers, which divide the *leftover* space equally — that
  centres the middle group between the two side sections, not on the display.
  With a full right-hand cluster and a near-empty left one, the clock sat ~230px
  left of true centre, and moved every time a right-hand widget appeared or
  vanished. Replaced with three anchored rows: left to the left edge, right to
  the right edge, centre to the screen's own centre. Measured after: centre ink
  midpoint 955 against a screen centre of 960.
- [x] **Five widgets were off the new bar rhythm** — Obs, Discord, Agents,
  ActiveWindow and Toggles still padded themselves with
  `Style.spacing.controlPaddingX` after the rest moved to
  `Style.bar.itemPaddingX`. Two of them (Obs, Discord) are in the live layout.
- [x] **20 repeated colour literals** across Obs, Discord and Weather. These are
  the deliberate never-theme-them colours (record red, Discord's speaking green,
  MeteoAlarm awareness levels), but Obs alone spelled the same three values
  eleven times — eleven places to disagree. Hoisted into `Color.semantic`, which
  also gives the rule a place to be written down.
- [x] **`weather-field.sh` duplicated the radar's zoom and tile size.** Changing
  the radar's zoom would have silently misaligned every arrow and isobar over
  the image with nothing to catch it. The field now derives its extent from the
  radar manifest's own `spanKm`, so there is one source of truth; no radar means
  no overlay, which is correct.

**Checks that came back clean**

- Registry coverage: every `*.manifest.json` id has a `BarSection` map entry and
  vice versa, with no file-name mismatches.
- `builtinShellConfig` and the live `~/.local/state/quickshell/shell.json` agree
  on all three sections (ground rule #5 — this drifted at the start of the
  session).
- All 67 escaped glyph codepoints verified present in `0xProto Nerd Font`'s cmap
  (ground rule #4).
- No `property var data/children/resources` shadowing (Appendix A).
- No `bar.foreground` misuse; the property is `barForeground` (Appendix A).
- No hardcoded `projects/arch-dotfiles` paths outside `Commons/Paths.qml`.
- Every plugin owning a `Process` has `keepLoaded: true` (ground rule #7).
- All four weather scripts carry the location-whitelist assertion.
- Every shell script parses and is executable; `obs-status.py` and the
  BetterDiscord plugin both parse.
- Clean QML log on start and after opening all eleven bar panels.
- Helper-process hygiene: `inotifywait` 1, `nmcli` 1, `wl-paste` 2.

## H11. UI coherence check

A pass over every surface — bar, the eleven hover panels, the launcher,
clipboard, power menu, overview, image picker, notifications, OSD, the
speed-test and Wi-Fi-QR panels, the startup splash — looking for places the
shell disagrees with itself rather than for bugs.

**Three card chromes for one kind of card.** Hovering a tray icon and
right-clicking it produced visibly different surfaces from the same icon:

| surface | border |
| --- | --- |
| every bar panel (`Ui/HoverPanel`) | `Color.menu.border` — foreground, full strength |
| tray right-click menu (`Ui/PopupCard`) | foreground at 0.45, set inline in `Tray.qml` |
| tray manage popup (`Ui/PopupCard`) | **`Color.popups.border` — accent** |

The manage popup was the only accent-outlined surface in the whole UI, and
nothing chose that; it was the `PopupCard` default nobody had overridden.
`PopupCard` now defaults to the same `Color.menu` role and the same
`panelPadding` as `HoverPanel`, and `Tray.qml`'s two ad-hoc overrides are gone.
A card hanging off the bar is a card hanging off the bar.

**Fourteen opacities doing four jobs.** `0.3 / 0.35 / 0.4 / 0.45 / 0.5 / 0.55 /
0.6 / 0.7 / 0.75 / 0.8 / 0.85` were all in use, chosen per call site by eye, so
neighbouring panels dimmed the same kind of label by different amounts. Added
`Style.emphasis` — `strong` / `dim` / `faint` / `disabled` — and converted 34
text-emphasis sites across 13 files. Structural opacities (rings, fills,
scrims, animation targets) keep their literals on purpose: they are not
hierarchy decisions.

**Typography off the scale.** `plugins/startup/Startup.qml` was the only file
in the shell with a raw `font.pixelSize` (22), raw `spacing: 14` and raw
`letterSpacing: 4`. It also drew with `Style.fontFamily` — the family
*requested* in `theme.json` — rather than `Style.font.family`, the family Style
actually resolved after its availability check. On a machine without the
configured font the splash would have rendered with a missing family while
every other surface fell back correctly. Now on the token scale, and using
`headerTracking` (+2.4, the wide setting) rather than `displayTracking` (-0.5,
which is for large numerals). `plugins/alert/Alert.qml` used a *spacing* token
as a font size (`Style.space(46)`) — it scales the same way, which is how it
got there; now `Style.font.displayLarge`.

Left alone deliberately: `Display.qml` compares against `Style.fontFamily` when
highlighting the selected font, which is correct — a font picker should show
what is configured, not what resolved.

**Clean:** radius is `Style.cornerRadius` at 54 of 62 sites, the rest being
`width / 2` circles; only 10 raw numeric spacing values remain shell-wide, all
0/1/2; no surface mixes the `menu` and `popups` colour roles any more.

## H12. Radar: a band, not a card inside a card

The radar read as glued on next to the hourly sparkline, and the reason was
structural rather than cosmetic. The sparkline is a bare `Canvas` spanning the
full content width with no chrome at all — it is simply part of the panel. The
radar was a **240px square, centred inside a 460px panel, with its own
background fill, its own border and its own corner radius**: a card inside a
card, narrower than every other row, outlined against the surface it sits on.
Three separate reasons to read as a guest.

- Now a full-width band, `height = width * 0.62`, with no fill, no border and
  no radius. The frames are transparent PNG overlays, so with nothing painted
  behind them the precipitation sits directly on the panel background and the
  crop edges are invisible.
- The square source is scaled to the band's **width** and cropped equally top
  and bottom. Two numbers — `imgSize` and `yOffset` — carry that transform, and
  everything drawn on top maps through them.
- **Range rings, their labels and the centre marker moved into the Canvas.**
  They were QML Items layered over the image, which meant a second coordinate
  system to keep aligned for no gain; one drawing now owns the whole overlay
  alongside the wind vectors, isobars and compass.
- Ring labels punch a gap in the arc rather than sitting on a pill — one less
  box. The first attempt left a sliver of the stroke peeking above the label,
  which reads as a rendering seam; the gap is now tall enough to swallow it.

## H13. UI coherence, second sweep — size, spacing, colour

The first sweep covered typography, card chrome and opacity. This one went at
the numbers underneath them.

**Row heights: eight of them, for two roles.** Panels listed the same sort of
thing at `20 / 22 / 24 / 26 / 28 / 30 / 32 / 34 / 38`. `Network.qml` alone used
**26, 28 and 32** for three rows of the same kind; `Display.qml` used 22, 28 and
32. Every one was a number typed at a call site. Added `Style.row.list` (a
selectable entry — an audio device, a Wi-Fi network, a toggle line, a media
player) and `Style.row.control` (a chip or button inside a panel), and assigned
15 sites **by role, not by a blind numeric map**. Grid cells (the calendar) and
bespoke chrome (the image carousel) keep their own numbers on purpose — they
are not rows.

**Panel widths: six, for cards read the same way.** `260 / 300 / 320 / 340 /
360 / 380 / 460`. Now `Style.panelWidth.narrow` / `.normal` / `.wide`; all
twelve hover panels are on one of the three. Weather keeps `wide` because it
genuinely carries more — three data tiers plus the radar.

**The fill system existed and was being bypassed.** `Style` already owns
`normalFillAlpha` (0.04), `hoverFillAlpha` (0.10), `selectedFillAlpha` (0.22),
`pressedFillAlpha` (0.28) and the `*Fill` / `*For` helpers built on them. Call
sites had nonetheless hand-rolled `Util.alpha(x, 0.07 / 0.08 / 0.10 / 0.12 /
0.14 / 0.15 / 0.16 / 0.18 ...)` — ten values doing the work of those four, so
panels tinted the same kind of surface by different amounts. Routed the
unambiguous ones back: five resting chip fills to `Style.normalFill`, and two
panels that had independently picked `accent @ 0.15` for an action chip to
`Style.selectedFillFor`. `Style.qml` now says outright that these are *the*
fill alphas and that call sites must use them.

Deliberately not swept: the remaining ad-hoc alphas are genuinely bespoke
surfaces (an avatar placeholder disc, a scrim, an alert tint keyed to its own
awareness colour). Rewriting those blind would have changed how several panels
look with no way to check each one, so they are named-once-per-file instead —
Discord's avatar backing was two identical literals and is now one property.

**Totals for this sweep:** 15 row heights, 12 panel widths and 7 fills moved
onto tokens; `Style.space(N)` call sites carrying a magic number dropped from
221 across 59 distinct values.

## H14. Notifications — toast and history list

**The same bordered card was doing both jobs.** `NotificationCard` is a
`BorderSurface` with a full outline and an opaque background — right for a
toast floating over the desktop, wrong for a row inside a panel that already
has edges. Four of them stacked made the history read as a pile of boxes, and
nothing else in this shell outlines its list rows.

Added a `variant`: `"toast"` keeps the card, `"row"` is transparent at rest and
lights up on hover like every other selectable row in the shell (audio devices,
Wi-Fi networks, tunnels). A critical row gets a left-edge accent rule instead
of the border it loses. Icon slot drops 32 → 24 in a row; at 32 the avatar
dominated a two-line entry and left the text looking like a caption hung off a
picture. Body clamps to 2 lines in a list, 3 in a toast, so rows scan.

**Neither surface said who or when.** `app` and `timestamp` were both
properties on the card and **neither was ever drawn** — so two toasts from
different apps were indistinguishable, and the history could not tell you
whether something arrived a minute or a week ago. Both now render as a faint
meta line above the summary, separated by a middot: at the same weight and
colour they otherwise read as one phrase. Times are relative and coarse — "4d",
not a date — because staleness is the question being asked. One timer on the
panel feeds every row rather than thirty rows each running their own.

**A real bug, not just ugliness: the history list was empty.**
`refreshHistory()` hung off the trigger's `onEntered` alone, so opening the
panel any other way — `quickshell ipc call bar open notifications`, or a
keybind — showed "Nothing recent" over a history directory with ten entries in
it. Exactly the trap the radar had. Now refreshes on the panel becoming
visible, plus a 4s poll while it stays open so a notification arriving with the
panel already up appears in the list instead of waiting for the next hover.

**The list was clipped mid-row** with nothing to indicate more below — it read
as a rendering cut. Added a bottom fade that hides itself at the end of the
list; one gradient, versus a scrollbar this shell has nowhere else.

## H15. Timestamps, and the Discord avatar gap

**Notification times are now clock times.** I had them as a relative age
("4d") on the argument that staleness is the question being asked. Wrong call
for a history you scroll: "2m" next to "3m" only tells you the order you
already knew, whereas `12:58` tells you it arrived during the meeting. Now
`HH:mm`, with the day prepended once it is no longer today, and "now" kept for
the first minute where a clock reading is noise. Toasts get the same treatment
via a shared clock on the service, so a popup replayed from history shows when
it originally arrived rather than a bare number with nothing to compare against.

**Discord avatars: the bug was in who, not in rendering.** Verified the render
path first with real CDN URLs — animated GIF, default PNG and the initials
fallback all draw correctly inside the `ClippingRectangle`, so nothing was
wrong with the images. The gap was in the plugin:

`UserStore.getUser()` only knows accounts the client has already loaded, so
anyone in the call you have never interacted with comes back **null** — and
`_avatarUrl(null)` returned `""`. Those people got a blank chip and a raw
snowflake for a name, which is precisely the set of participants you are least
able to identify without a picture. Discord's default avatar is derived from
the account id alone, so it is available even when the user object is not; the
plugin now falls back to it, and to the voice state's own nickname before
showing an id.

**A dim that had silently stopped working.** `ClippingRectangle` reparents its
children into an internal `contentItem`, so `parent.parent` from inside the
avatar `Image` no longer reached the delegate — `parent.parent.silenced`
evaluated to undefined and the muted-participant fade never applied. It failed
quietly because `undefined ? 0.5 : 1` is simply `1`. Addressed by id instead,
which is immune to a component reparenting its children.

Incidental: the notifications now visible in the history are real
`obs-browser-page` crash reports, which lines up with the `obs-browser-page`
coredumps already recorded in section I.

## H16. Wind field, compass, and a Canvas that took the whole overlay down

**A denser field without a denser fetch.** Arrows now sit on a 17x17 lattice
interpolated from the same 5x5 API grid. Open-Meteo bills per location, so 289
real samples every nine minutes would be a quota problem; wind at ~100 km
spacing is a smooth field, so interpolating between the 25 real samples is both
free and physically reasonable.

The **components** are interpolated, not speed and direction. Averaging
bearings is wrong at the wrap: halfway between 350° and 10° is 0°, but the mean
of those numbers is 180° — an arrow pointing exactly backwards.

Then toned down twice on feedback: arrow length scaled to the lattice (so
raising the density shrinks them rather than overlapping them), alpha dropped
to 0.13–0.42, and speed shaped through a sqrt so gentle flow stays legible
while the top of the range stays distinct. The field should be something the
eye reads *through* — the radar is what the panel is for.

**The compass was a circle with a crosshair through it.** Crude alone, and with
a few hundred arrows crossing the same pixels it had no ground of its own.
Redrawn as a rose: a backing disc so the field passes behind it, a thin ring,
four ticks with north the long one, and a filled north needle in the accent. A
cross through the middle fights the needle for the same space and reads as a
gunsight, so it is ticks.

**The centre marker** was a flat 9px disc — fine over five big arrows, far too
heavy over a few hundred small ones, where it read as a blob sitting on the map
rather than a position on it. Now ~3px with a background ring, which is what
keeps it findable among arrows of its own colour.

**The bug this turned up: one bad radius blanked the entire overlay.**
`Weather.qml[1167]: Error: Incorrect argument radius`. The wind block declared
`var reach` for arrow length and the ring block declared `var reach` for the
map's reach in km — and `var` is function-scoped, so those were **one variable
in one function**. A `ctx.arc()` that throws aborts the whole `onPaint`, so a
single nonsense ring radius took the rings, the arrows, the isobars and the
compass with it: the radar simply had no overlay and nothing said why until the
raw log was read. Renamed to `reachKm`, and every radius the canvas computes is
now finite-checked before it reaches `ctx.arc`.

## H17. Notification body clamp scales with the list

A single notification in the history had its message elided at two lines —
"…in the…" — above roughly 40px of empty panel. The clamp was doing its job
and the job was wrong for that case.

The two-line limit exists so a long list keeps uniform row heights and stays
scannable. With one entry there is nothing to scan past: it is a detail view,
and eliding it hides the message while leaving the space it would have used
empty. So the panel now decides, because only it knows how many rows there are
— up to 10 lines with one or two entries, back to 3 beyond that, where uniform
heights matter again and the panel scrolls with its bottom fade.

Verified both ways: one entry renders the full body and the panel grows
230 → 268px; five entries clamp at 3 lines, cap at the 400px panel maximum, and
fade at the bottom edge.

## H18. Radar was slow to open — three separate reasons

**Downloads were sequential.** Twelve frames fetched one after another is
twelve round trips end to end, and that was the single biggest cost. They are
independent files from one CDN with no ordering to preserve, so they now go
through `xargs -P 6`: wall time becomes roughly the slowest frame rather than
the sum of all of them. Measured cold, with the cache deleted: **6.5s for 12
frames**.

**A refresh blanked the loop it was replacing.** The script deleted every frame
before downloading the new ones, so for the whole length of a refresh the cache
held nothing and a panel opened in that window showed "Loading radar…" over a
loop that had been perfectly good a second earlier. Frames now build up in a
staging directory and move into place only once the complete loop is ready.
Verified by forcing the manifest stale and polling the live directory through a
refresh: **12 frames present at every second**, manifest flipping to the new
one at t=8s.

**It only fetched when you opened the panel.** That was a deliberate call —
a dozen PNG downloads should not happen unless somebody looks — and it was the
wrong trade: opening the panel started a cold fetch whenever the nine-minute
cache had lapsed, which is most times. There is now a ten-minute background
prefetch, matching the cadence at which RainViewer's own index actually
advances (more often re-downloads identical PNGs; less often and it is stale
when you look). `triggeredOnStart` covers the first open after a shell restart,
which is otherwise the one occasion guaranteed to be cold.

Cost of the change: one round of downloads (~200 KB) per ten minutes whether or
not the panel is opened. That is the price of the panel being instant, and it
was the explicit ask.

Measured after: panel opened and **fully rendered — precipitation, arrows,
isobars, rings, compass — 1.5s after the open**, against several seconds of
"Loading radar…" before.

## H19. One scrim, and two dead wallpaper buttons

**Overlay scrims disagreed.** There were two values: the wallpaper picker dimmed
the desktop to 0.75, while the launcher, power menu, clipboard, overview,
reminder flow and speed-test overlay all used `Color.menu.scrim` at 0.94.
Opening one overlay after another visibly changed how much desktop was left,
which reads as three different applications rather than one shell.

Settled on the picker's 0.75 as a single `Color.scrim`, with `menu.scrim` and
`imagePicker.scrim` both pointing at it — so all six surfaces moved with no
call-site churn. `polkit.scrim` keeps its own lighter value on purpose: an
authentication prompt should leave the window that triggered it visible.
Verified by sampling the same desktop strip under each overlay: identical mean
across launcher, power menu and picker.

**The "missing text" was my own test.** I had summoned `panel.image-picker`
with an empty payload while checking the scrim, and `showLabels` defaults to
false — so a labelless picker appeared on screen. The real launcher passes
`showLabels: true` and the name renders correctly ("Mountain2").

**But it sat next to a real bug.** Both in-shell routes to change the
wallpaper — the Display panel's button and double-clicking the desktop — ran
`switch-wallpaper.sh` with no arguments. That path falls through to an
fzf+chafa picker, which needs a terminal; launched detached from the shell it
has no tty, so both controls started a program that immediately gave up and
nothing appeared. They now call `wallpaper-picker.sh`, which is the wrapper
that summons the native overlay — and the only caller that passes
`showLabels: true`.

Addressed by repo path rather than by name: repo-root scripts link into
`/usr/local/bin`, not `~/.local/bin`, so `Paths.bin()` would have been wrong
here and PATH resolution is not something a detached process should depend on.

## I. Stability — two render-thread crashes, unresolved

Quickshell died twice during this session. Both are on the **render thread**,
neither has any QML output before it, and the two stacks are different:

- `SIGABRT` — `QSGRenderThread` → `QWaylandGLContext::swapBuffers` → an abort
  inside `libgallium`.
- `SIGSEGV` — `QSGBatchRenderer::Renderer::render` → `ensurePipelineState` →
  `QOpenGLProgramBinaryCache::ProgramDesc::cacheKey` → `QCryptographicHash` →
  OpenSSL → jemalloc.

Both happened while OBS was recording with browser sources on the UHD 620, and
across a session with ~20 shell restarts. Cleared `~/.cache/qtshadercache-*`
after the second one, which is the cache the second stack walks. **Not
diagnosed** — recorded rather than quietly assumed fixed. If it recurs,
`coredumpctl info quickshell` will say whether it is one of these two paths or
a third.

## J. CPU and memory

Measured, not guessed. A stripped-down `shell.qml` establishes the floor that
Quickshell + Qt + Mesa cost on this machine: **249 MB RSS**, of which 214 MB is
shared library mappings (libLLVM and libgallium alone are ~110 MB) and only
35 MB is this process's own memory. Everything above that is ours.

- [x] G1 — **Wallpaper decoded at source resolution, not display resolution.**
  `Background.qml` had no `sourceSize`, so a 3840x2160 wallpaper on a
  1920x1080 output decoded to a full 33 MB RGBA buffer — four times the pixels
  that can ever be shown — and up to three existed at once mid-crossfade.
  Bisection attributed **44 MB RSS** to the background alone.
- [x] G2 — `revealMask`'s `layer.enabled: true` was unconditional, holding a
  full-screen framebuffer permanently to serve a 420 ms animation. Now gated
  on the crossfade actually running. Mipmaps dropped from the transition
  frames too: with `sourceSize` matching the drawn size there is no
  minification for them to serve, and they cost a third of each texture.
- [x] G3 — **Every other uncapped image decode.** The wallpaper picker loaded
  4K originals *and* 4K thumbnails into a 768px box; clipboard screenshots
  decoded at full size per visible row; album art at whatever the player
  publishes, drawn in a 72px frame. All capped to their drawn size.
- [x] G4 — Clock's calendar grid rebuilt all 42 delegates once a second while
  the panel was open (B11).
- [x] G5 — The OBS helper is not started until OBS is seen (see F1).

**Result: 393 MB -> 376 MB RSS, 178 MB -> 134 MB of own memory (-25%)** — and
that is *after* adding two new widgets. CPU was already low and stayed there:
0.26% of one core at idle before, 0.35% after, with the helper processes
contributing another ~0.2%.

Not pursued: the 110 MB of Mesa/LLVM mappings are shared with every other GL
client and are not the shell's to reclaim; the remaining ~90 MB over the floor
is QML engine and scene-graph cost spread thinly across twenty-odd components,
with no single contributor worth more than a few MB.
