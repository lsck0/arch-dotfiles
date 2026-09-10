# SPEC conformance matrix

Written from a local audit of `configs/quickshell/`, not from web research.
This is the spine document: it says what the SPEC asks for, what exists
today, and what the actual gap is. The web-research docs (01, 03-06) fill
in *how* to close the gaps this file identifies.

SPEC = the prompt recorded verbatim in `prompts.md`, including the two
weather additions made 2026-09-01 (both now appended there):

> it should also have a comprehensive weather widget with todays weather
> (temp, sky, humid) as well as a 3 day forecast. it should use the current
> location but NOT REVEAL IT

> another addition to the spec: on the weather display i also want an hourly
> prediction. so current weather (with temp, humidity, sun, uv levels, wind,
> wind direction etc) temp and humid and rain change per hour for the day and
> then the 3 day temp+sky (sunny,rain,windy) forecast

Field-by-field mapping of both onto the Open-Meteo API is in
`08-weather.md` §6.

**Headline: the shell is much further along than "massively lacking"
suggests — ~15k lines of QML, 22 registered bar widgets, a working
notification daemon, launcher, and lock screen. The gaps are real but
specific.**

---

## 0. The two findings worth reading first

### 0a. `shell.qml`'s defaults diverge from the live layout

**Corrected 2026-09-01.** An earlier version of this section claimed six
built widgets — including `bar.tray` and `bar.battery` — were "never placed
in the bar," and called adding them the highest value-to-effort item in the
SPEC. **That was wrong, and it was wrong because it read only `shell.qml`.**

The layout that actually drives the bar is the runtime state file at
`~/.local/state/quickshell/shell.json` (`shell.qml:50`), which **overrides**
the `builtinShellConfig` literal. That file already contained `bar.tray`,
`bar.battery`, `bar.indicators`, `bar.keyboard-layout`, and
`bar.system-update` — the shell appends newly-registered widgets to the user
config automatically as their manifests appear. So the system tray and
battery were on the bar the whole time.

The real finding is a **divergence**: `shell.qml`'s builtin defaults are
stale relative to the live state file. That matters because the builtin is
the tracked-in-git fallback — anyone who deletes the state file, or sets
this repo up on a fresh machine, gets the stale bar rather than the real one.

- [ ] Reconcile `builtinShellConfig` in `shell.qml` with the live layout, so
  the tracked default reproduces the actual bar.

**Lesson for future audits of this shell: `shell.qml` is not the source of
truth for the bar layout.** Read `~/.local/state/quickshell/shell.json`
first, and treat the builtin as a fallback only.

For reference, the widgets that had manifests but were missing from the
*builtin defaults* (all present in the live layout):

| Widget id | File | In SPEC? |
| --- | --- | --- |
| `bar.tray` | `Tray.qml` | **YES — "system tray" is a named SPEC bullet** |
| `bar.battery` | `Battery.qml` | **YES — "battery if applicable"** |
| `bar.indicators` | `Indicators.qml` | no |
| `bar.keyboard-layout` | `KeyboardLayout.qml` | no |
| `bar.system-update` | `SystemUpdate.qml` | no |
| `bar.spacer` | `Spacer.qml` | no (layout utility) |

All of these are live on the bar today. The SPEC's "system tray" and
"battery if applicable" bullets are **already satisfied**.

### 0b. The media widget is on the wrong side

SPEC puts datetime and media in the **middle**. Current layout:

```qml
left:   [ bar.app-menu, bar.workspaces ]
center: [ bar.clock, bar.weather ]
right:  [ bar.active-window, bar.media, bar.system, bar.agents, bar.toggles,
          bar.microphone, bar.audio-io, bar.display, bar.network,
          bar.news, bar.costs, bar.notifications ]
```

`bar.media` is in `right`. Moving it to `center` is another one-line
change — but see §4, because the panel-anchoring constraint means a
center-mounted media widget's hover panel has the same ~950px reach problem
the clock already has. **Do not move it until anchoring is fixed.**

Also note the current bar carries six widgets the SPEC never asks for
(`active-window`, `agents`, `toggles`, `microphone`, `news`, `costs`,
`weather`). The SPEC is not obviously a request to remove them — it reads
as a description of the target bar, and the owner built these deliberately.
**Open question for the owner: is the SPEC's widget list exhaustive
(remove the extras) or additive (keep them)?** Recommend treating it as
additive and confirming, since deleting working widgets is destructive and
easily reversed if wrong.

---

## 1. Top-level SPEC items

| SPEC item | State | Gap |
| --- | --- | --- |
| App Menu (replacing walker) | ✅ built — `plugins/appsearch/` + `bar.app-menu`, purpose-built picker over `AppLibrary`/`AppSearch.js` | `walker-bin` still installed; see §5. Launcher feature depth (calc/web/file modes, frecency) is a research item — doc 06 §2 |
| Wallpaper Switcher (from omarchy) | ⚠️ partial — `scripts/switch-wallpaper.sh` (external, pywal); `plugins/image-picker/ImagePicker.qml` is a **complete 603-line thumbnail picker that was never wired up** | Mostly wiring, not building. Also: `awww-daemon` runs alongside the QML crossfade — two renderers at once. Doc 06 §1 |
| Lock Screen (replacing hyprlock) | ⚠️ built but **never actually invoked** — PAM + `WlSessionLock`, visuals from omarchy's `LockView.qml`; verified only via a throwaway non-locking preview overlay | **Unblocked:** set Hyprland `misc:allow_session_lock_restore` (verified `false` and unset today) so a QML crash while locked is recoverable, then test. Doc 06 §3. Keep `hyprlock` until verified |
| The bar (replacing waybar) | ✅ built and running | `waybar` still installed + `configs/waybar/` still present. See §5 |
| Multiple monitors | ✅ `Variants` over `Quickshell.screens` in `Bar.qml`, `Background.qml`, `Osd.qml`, `notifications/Service.qml`, `KeyboardPanel.qml` | **Hot-plug behaviour unverified.** Per-monitor widget sets not supported (one layout for all screens). Doc 06 §4 |
| Notification Widget | ✅ built — native daemon replaced mako; `bar.notifications` with DND + history | `mako` still installed. **History panel renders plain text only** — rich card exists but is used only for popups; see §2a |
| Themed by wallpaper (pywal) | ✅ `Commons/Color.qml` fed solely from `~/.cache/wal/colors.json` | Live re-theme on wallpaper change, and animated palette transitions, are open. Doc 06 §1 |
| Techy/modern/sleek, "impress" | ⚠️ subjective | Doc 06 §5 is the answer to this and to "any other REALLY cool things?" |

## 2. Bar widgets vs SPEC

### Left

| SPEC | State |
| --- | --- |
| Arch icon, click opens app selector | ✅ `AppMenu.qml` (32 lines) |
| Workspaces (like waybar) | ✅ `Workspaces.qml` (117 lines), incl. scroll-to-switch (wheel delivery still unverified) |

### Middle

| SPEC | State | Gap |
| --- | --- | --- |
| datetime: date + time | ✅ `Clock.qml` | — |
| ↳ timezones (NA east/west, UK, NZ) + timetravel slider | ✅ **already built** — `timezone-offsets.sh` + a -24h/+24h `PanelSlider`, and the slider scrubs the calendar too | — |
| ↳ calendar of current month | ✅ built | — |
| ↳ "remind me in X" | ❌ **not in the clock panel** | `plugins/reminders/` exists standalone (Phase 6) + `scripts/notification-send.sh`; needs wiring into the clock panel |
| ↳ pomodoro timer with notifications | ❌ **not implemented anywhere** | New build. Notification path already exists |
| media: sound visualizer | ❌ **not implemented** | Biggest single gap. `cava` **is already installed**. Doc 03 |
| ↳ on hover: transport + rich now-playing | ❌ **no hover panel at all** — `Media.qml` is 82 lines with only a tooltip; next/prev are middle/right-click | Needs a real panel: art, album, seek, multi-player. Doc 03 |
| weather: today temp + sky + humidity | ⚠️ partial — `Weather.qml` (73 lines) shows a glyph + condition/temp in a **tooltip only**; humidity missing | Doc 08 |
| ↳ 3-day forecast | ❌ not implemented | `wttr.in?format=%C\|%t` returns current conditions only; needs `?format=j1` or a different provider. Doc 08 |
| ↳ use current location but **NOT REVEAL IT** | ⚠️ **partly by accident, and broken under tunnels** — see §2b | Doc 08 |

### Right

| SPEC | State | Gap |
| --- | --- | --- |
| system tray | ✅ live on the bar (`Tray.qml`, SystemTray-backed) | — |
| system: cpu/gpu%, (v)ram, battery | ⚠️ partial — `System.qml` shows cpu%, freq, RAM, temp, iGPU% | No VRAM; battery is a separate unplaced widget |
| ↳ cpu/gpu **name** | ❌ | Doc 04 |
| ↳ usage %, memory, clock rate, temperature | ✅ | — |
| ↳ **voltage** | ❌ `system-stats.sh` documents vcore as unavailable on this hardware | Needs an honest answer + substitute (RAPL watts). Doc 04 |
| ↳ ram/**vram** usage | ❌ VRAM missing | Intel iGPU VRAM has no simple sysfs path. Doc 04 |
| ↳ battery (if applicable) | ✅ live on the bar (`Battery.qml`, `Quickshell.Services.UPower`) | — |
| ↳ powermode toggle | ✅ `toggle-powermode.sh` (TLP, 3-state) exists and is the correct pattern | Confirm it is surfaced in the System panel per SPEC |
| network: is there internet, lan or wifi | ✅ `Network.qml` (426 lines) | — |
| ↳ wifi/lan details, ip mac | ✅ `network-details.sh` | — |
| ↳ internet speed test | ✅ `plugins/speedtest/` | — |
| ↳ network selection | ✅ `network-wifi-scan.sh` / `-connect.sh` | — |
| ↳ tunnel selection (tor, vpn, wireguard) | ✅ rows for Tor / ProtonVPN / WireGuard homeserver, correctly shelling to `toggles/` | — |
| ↳ bluetooth | ⚠️ works but **inline `bluetoothctl` in QML** | Toggle violation — doc 02 §5c |
| ↳ mobile network | ❌ n/a — **no cellular modem on this hardware** (widget already says so) | Confirm hardware finding; doc 05 |
| ↳ localsend | ❌ **no integration at all** | Doc 05 §4 evaluates localsend vs KDE Connect |
| ↳ disable internet / bt / mobile, full offline mode | ⚠️ offline mode exists but **inline `rfkill block all` in QML** | Toggle violation + safety review — doc 02 §5b, doc 05 §5 |
| audio: in/out device selection | ✅ `AudioIO.qml` (241 lines), Pipewire-bound, `pactl` for default-device switching | — |
| ↳ in/out volume | ✅ | — |
| ↳ global mute / **deafen** | ⚠️ mute yes, **no deafen** — no combined in+out mute anywhere in `AudioIO.qml` | Small addition: one action muting sink + source together |
| monitor: screen brightness | ✅ `Display.qml`, `brightnessctl` | Hand-rolls a slider instead of reusing `Ui/PanelSlider.qml` |
| ↳ screen scale | ⚠️ runtime-only + clobbers resolution/position | Toggle violation — doc 02 §5d |
| ↳ font selection (any installed font) + size | ❌ **4 hardcoded fonts, `sed -i` from QML, incomplete coverage** | Worst violation — doc 02 §5a. **Blocked on the font-token split, §4** |
| ↳ wallpaper selection (button opens the real one) | ⚠️ launches external `switch-wallpaper.sh` | Wire to native `image-picker`. Doc 06 §1 |
| notifications: disable all | ✅ DND via `toggle-dnd.sh` — correct pattern | — |
| ↳ rich list w/ image + text, click opens source | ❌ **history panel is plain text only** — see §2a | Reuse `NotificationCard.qml` in the history list |

### 2a. The notification history panel does not use the rich card

`plugins/notifications/components/NotificationCard.qml` already supports
everything the SPEC asks for: a real image slot with app-icon and Nerd Font
glyph fallbacks (`smallIconSource`, `iconSource()` handling `file://` /
`image://` / `Quickshell.iconPath()`), and a left-click `cardClicked()`
action (right-click dismisses).

But it is only used for the **popup toasts**. The bar's history panel in
`Notifications.qml:143-166` renders its own delegate — two plain `Text`
elements, `app — summary` and `body`. No image, no click handler.

So the SPEC line "a list of notifs that arrived shown rich with image and
text and opening the source on click" is unmet in two of its three parts,
and the fix is mostly reuse rather than new code: render the history list
with `NotificationCard` and wire `cardClicked()` to activate the
notification's default action / launch its `desktopEntry`. The history
model will need to retain the image and hint fields for that to work —
check what `NotificationLogic.js` currently persists.

### 2b. Weather: the location requirement conflicts with the VPN toggles

`Weather.qml` currently runs:

```
curl -s --max-time 8 "wttr.in/?format=%C|%t"
```

wttr.in with no location argument geolocates **from the requesting IP**.
That has two consequences for the new SPEC line.

**On "NOT REVEAL IT":** the widget satisfies the *display* half today, but
only incidentally — it renders nothing but a glyph and a temperature
because that is all it fetches. As soon as it grows a comprehensive panel,
every conventional weather-UI element becomes a potential leak: a place
label, obviously, but also sunrise/sunset times, a timezone, or a
"feels like" figure paired with anything locale-specific. The panel design
has to exclude these deliberately rather than inherit them from a template.
Separately, the *disclosure* half is not satisfied at all: the user's IP
goes to wttr.in on every poll.

**The real complication — tunnels.** This repo has `toggle-tor.sh`,
`toggle-vpn.sh`, and `toggle-protonvpn.sh`, and the network widget exposes
all three. IP geolocation returns the **exit node's** location, so whenever
a tunnel is up the widget silently shows a different country's weather
while looking completely normal. This is a live correctness bug in the
current widget, not just a design concern for the new one — and it is the
reason "use the current location" cannot be implemented as "let the
provider infer it from our IP."

There is also a genuine tension the owner may need to arbitrate: a *fixed*
coarse location is stable under tunnels and leaks nothing new, but stops
being "current" when travelling; a *live* location source follows travel
but needs something like GeoClue2 (WiFi-based, tunnel-independent) rather
than IP inference. Doc 08 researches the layered options and recommends a
precedence order.

## 3. What is already good (do not rebuild)

Worth stating explicitly so research findings don't cause churn:

- **Multi-monitor** is already done the idiomatic way (`Variants` over
  `Quickshell.screens`). Reject any recommendation to restructure it.
- **Hover-driven panels are deliberate.** The SPEC says "on hover" nine
  times, which *confirms* the one intentional deviation from upstream's
  click-to-toggle. Any research doc recommending click-to-toggle is wrong
  for this repo.
- **No theme-override layer.** `Color.qml`/`Style.qml` deliberately omit
  upstream's `shell.toml` theming because there is exactly one pywal-fed
  theme. Not a fidelity gap; do not port it back.
- **The timetravel clock already exists** and is better than the SPEC
  describes (the slider scrubs the calendar as well as the zone list).
- **`toggle-dnd.sh` and `toggle-powermode.sh` are the correct patterns** —
  cite them, don't redesign them.

## 4. Structural blockers (resolve before building panels)

### 4a. Panel anchoring — blocks both middle widgets

Every hover panel anchors top-right regardless of trigger. `Clock.qml`
documents the consequence and the two approaches already tried and failed:

- `mapToGlobal` — Wayland gives clients no true global coordinates.
- `mapToItem(bar.contentItem, ...)` — the binding evaluated once before
  `RowLayout` finished laying out and never recomputed (a QML reactivity
  gap, not coordinate math).

The current mitigation is that *all* panels share one position, so hover
transit from any right-section trigger is geometrically guaranteed. The
clock trigger is ~950px away and needs one continuous motion inside
`hoverCloseTimer`'s grace window.

**This is why it blocks the SPEC:** the SPEC puts *both* middle widgets
(datetime, media) behind hover panels. Fixing anchoring is a prerequisite
for the media panel and for moving `bar.media` to center (§0b).

A third approach not yet tried: have `BarWidget` report its laid-out x via
a property the panel binds to, updated on `RowLayout` `widthChanged` /
`Component.onCompleted` + a layout-change signal — i.e. fix the
*reactivity* of the `mapToItem` approach rather than the coordinate source.
Worth prototyping before accepting the right-anchored compromise forever.

### 4b. Font-token split — blocks font selection

`Style.fontFamily` is pinned to `0xProto Nerd Font` and `Style.font.family`
is used for **both body text and every icon glyph**. SPEC's "any installed
font" would silently break every icon. Requires splitting
`Style.font.ui` (selectable) from `Style.font.icon` (pinned) and sweeping
every glyph call site *before* `toggle-font.sh` may touch quickshell. Full
detail in doc 02 §6.

## 5. Decommissioning

`waybar`, `hyprlock`, `walker-bin`, and `mako` are all still installed, and
`configs/waybar/`, `configs/walker/`, `configs/wlogout/` are still in the
repo and still symlinked by `configs/link.sh`. Each has been functionally
replaced.

Keeping them as a fallback is a legitimate choice — especially `hyprlock`,
given the lock screen has never been invoked for real (§1). But it should
be a *recorded* choice rather than drift. **Recommendation: keep
`hyprlock` until the quickshell lock screen is verified end-to-end, then
remove; decide explicitly on the other three.** Removal touches
`install.sh` package lists and `configs/link.sh`, so it is a real change,
not a cleanup afterthought.

## 6. Suggested order of work

1. Reconcile `shell.qml`'s stale `builtinShellConfig` with the live layout
   (§0a) so the tracked default reproduces the real bar.
2. `toggle-bluetooth.sh` extraction (doc 02 §7 step 1).
3. Fix panel anchoring reactivity (§4a) — unblocks everything in the middle.
4. Media: cava visualizer + rich MPRIS panel (doc 03) — biggest visible win.
5. Pomodoro + "remind me in X" into the clock panel.
6. Font-token split, then `toggle-font.sh` (doc 02 §7 steps 3-4).
7. `toggle-offline.sh` + `toggle-monitor-scale.sh`.
8. Native wallpaper picker wired to `image-picker` (doc 06 §1).
9. Lock-screen verification, then decommissioning (§5).
10. Cool-things backlog (doc 06 §5).
