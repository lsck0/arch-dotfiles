# Media widget: spectrum bar + hover panel — research

Target: replace the current 82-line `Media.qml` (play/pause glyph + "title —
artist" text, tooltip-only) with a live spectrum visualizer and a hover
panel with transport controls + rich now-playing view.

---

## RECOMMENDATION

1. **Spectrum source: `cava` as a subprocess, driven through a ref-counted
   singleton, `output.method = raw` / ASCII / stdout.** Quickshell has no
   FFT primitive. It *does* have `Quickshell.Services.Pipewire.PwNodePeakMonitor`
   (real native peak metering, zero subprocess — see §1c) but that's a single
   scalar "how loud right now", not per-band spectrum data, so it can't drive
   distinct moving bars. `cava` is already installed and this is the pattern
   every real Quickshell shell with a visualizer uses (DankMaterialShell,
   caelestia, RiceOs-style forks). Do **not** build a C++ Quickshell plugin
   (`Caelestia.Services.CavaProvider`) for this — that's what caelestia-dots
   did, but it means shipping and rebuilding a compiled `.so` against
   libcava/Quickshell headers on every Quickshell upgrade, for a bar widget
   that draws ~6 bars. Subprocess `cava` + `SplitParser` is ~40 lines of
   QML, no build step, no ABI coupling. Give it its own generated config
   file (below) instead of touching `~/.config/cava/config`, so it never
   collides with a terminal-cava config the user might set up separately.

   Exact config to generate at runtime (DankMaterialShell's proven config,
   trimmed to this widget's needs — 6 bars is plenty for a ~24-30px tall
   bar segment; bump `bars=` if the hover panel wants a wider display):

   ```ini
   [general]
   framerate=25
   bars=6
   autosens=0
   sensitivity=30
   sleep_timer=3
   lower_cutoff_freq=50
   higher_cutoff_freq=12000

   [output]
   method=raw
   raw_target=/dev/stdout
   data_format=ascii
   channels=mono
   mono_option=average

   [smoothing]
   noise_reduction=35
   integral=90
   gravity=95
   ignore=2
   monstercat=1.5
   ```

   `sleep_timer=3` makes cava itself go quiet (near-zero CPU) after 3s of
   silence, without detecting silence in QML. `autosens=0` + fixed
   `sensitivity` avoids visible bar "recalibration" on playback
   start/stop. `data_format=ascii` + `raw_target=/dev/stdout` means each
   line is just `N1;N2;N3;N4;N5;N6\n`, trivially parsed with
   `line.split(";")` — no binary framing.

2. **Only run `cava` while it's actually needed.** Wire this as a
   `pragma Singleton` service (`Services/Cava.qml`) with `property int
   refCount`, `Process { running: refCount > 0 }`, following
   DankMaterialShell's `CavaService`/`Ref` pattern exactly (§1a/§1b below).
   The bar widget's spectrum `Item` holds a `Ref` only while
   `visible && a player is Playing`; the hover panel holds a second `Ref`
   only while the panel is open. refCount naturally drops to 0 (process
   exits) when nothing is playing or nothing is watching — this is the
   answer to "how do you stop burning CPU when nothing is playing" and it's
   cheap in QML, no manual kill-on-idle logic needed.

3. **Rendering: `Repeater` + `Rectangle`, not `Canvas`/`Shape`/`ShaderEffect`.**
   At 6 bars and ~24-30px height this is a trivial `Row` of `Rectangle`s
   whose `height` is bound to a smoothed value, each with a
   `Behavior on height { NumberAnimation { duration: 90;
   easing.type: Easing.OutQuad } }` for inter-frame smoothing (cava already
   emits at 25fps with its own `smoothing` stage, so QML only needs to
   interpolate between the ~40ms steps, not do real signal smoothing).
   `ShaderEffect` (what DankMaterialShell uses, §1a) is faster to paint but
   requires shipping a compiled `.qsb` shader and vector-packing bars into
   `vec4`s — worth it at their scale (multiple visualizer instances across
   bar/lock/dash), not worth it here for one 6-bar widget. `Canvas` is
   strictly worse than `Repeater`+`Rectangle` for straight vertical bars:
   it repaints as an image on every frame instead of letting the scene
   graph batch/animate rectangles, and buys you nothing since there's no
   curve-drawing need. `QtQuick.Shapes` (caelestia's `CoverVisualiser`,
   §2c) is for the fancy radial-around-album-art look — reserve that idea,
   if ever, for the hover panel's "rich" view, not the compact bar segment.

4. **Rich hover panel: extend the existing tooltip → panel idiom, but for
   hover not click.** This repo's panel plugins (`wifiqr`, `emojis`,
   `notifications`, …) open on click via `bar.togglePanel(id)` as separate
   `PanelWindow`s with their own `manifest.json`. This spec is explicitly
   hover-driven, a mechanism this repo doesn't have yet for bar widgets —
   build a `PanelWindow` the widget shows on `hoverArea.entered` (with a
   short close-delay `Timer` so crossing the gap between bar and panel
   doesn't flicker-close it — same idea as `_switchHoldTimer` in
   DankMaterialShell's media tab, §3e) and hides on `exited` with nothing
   hovered. If implemented as a `plugins/bar/*` panel with its own
   manifest owning the `cava` `Process` (via the `Ref`/refCount pattern) or
   any other long-lived subprocess, **set `"keepLoaded": true`** in that
   manifest, matching `wifiqr`/`emojis`/`notifications`/`speedtest`/
   `disk-speedtest`/`reminders` in this repo — without it the `Loader` in
   `shell.qml` tears the `Process` down as soon as the panel closes, before
   `cava` (or a download `Process` for album-art caching) can exit cleanly.

5. **Album art:** try `player.trackArtUrl` first, fall back to
   `player.metadata["mpris:artUrl"]` (some players populate one and not the
   other). Handle three cases: `file://` (use directly), `http(s)://`
   (must download once to `Image`-cacheable local storage — QML `Image`
   *can* load `http://` directly but re-fetches on every binding
   re-evaluation and shows nothing while loading), and empty (show a
   pywal-tinted placeholder glyph, never a broken-image icon).
   DankMaterialShell's full `TrackArtService` (§3b) solves problems
   (multi-player art fallback races, YouTube thumbnail fallback chains,
   content-hash cache keys) this bar doesn't have — a much smaller version
   suffices here: on `trackArtUrlChanged`, if the url starts with `http`,
   shell out to `curl -sL -o
   $XDG_CACHE_HOME/quickshell/media-art/<sha1 of url> <url>` via a one-shot
   `Process`, then point `Image.source` at the local `file://` path once it
   exits 0; if already `file://`, use as-is; if empty, show the
   placeholder.

6. **Position/seek: poll, don't bind directly.** `MprisPlayer.position` is
   documented (Quickshell source, §3a) to *not* update reactively on its
   own — you must manually re-emit `positionChanged()` on a cadence while
   watching it. Use a `Timer` (interval 1000, `running: panelOpen &&
   playbackState === Playing && !isSeeking`) for the numeric "1:23 / 3:45"
   labels, and a `FrameAnimation` (same guard) only while the panel is open
   and the pointer is over the seek bar, so a smooth-dragging slider
   doesn't cost a timer tick every frame all the time. Guard all seek UI
   behind `player.canSeek` — many players (browsers, some MPRIS bridges)
   don't support it. Same "check the `canX`/`xSupported` twin before
   rendering the control" rule applies to `loopSupported`/
   `shuffleSupported`/`canGoNext`/`canGoPrevious` — MPRIS compliance
   varies wildly per player (called out explicitly in Quickshell's own
   source doc-comment, §3a).

7. **Multi-player picker:** keep the existing widget's "prefer Playing,
   else first" default for the *compact bar segment* (already correct —
   don't change it), but in the hover panel surface `Mpris.players.values`
   as a small icon row (app icon or a generic note glyph + `identity`) so
   the user can switch which player's now-playing info the panel/spectrum
   reflects, mirroring DankMaterialShell's player-cycle button (§3c).
   Don't build a dropdown — with normally 1-2 active players a row of 2-3
   icons is enough and stays inside the hover-panel-not-click constraint.

8. **Loop/shuffle:** simple icon toggles, each `visible:
   player.loopSupported` / `player.shuffleSupported`, cycling
   `MprisLoopState.None → Playlist → Track → None` on click for loop and
   `player.shuffle = !player.shuffle` for shuffle. Gate both behind
   `player.canControl` too.

9. **Theming:** everything pulls from `Commons/Color.qml`
   (`Color.foreground`/`Color.accent`/etc., fed from
   `~/.cache/wal/colors.json`) and `Commons/Style.qml` tokens, same as the
   rest of this bar — no new color source, no gradient/blur libraries. A
   "dominant color from album art" backdrop (caelestia's `Visualiser.qml`
   blurs the wallpaper, §1b) is out of scope: this repo is pywal-only by
   design and album art isn't guaranteed per track/player, so it can't be
   the *primary* palette source. If wanted later, treat it as a subtle
   backdrop tint behind the panel, never replacing the pywal roles.

10. **playerctl vs native Mpris, and per-app volume (§4):** stick with
    native `Quickshell.Services.Mpris` — `playerctl` is just a slower
    subprocess wrapper around the same DBus calls Quickshell already
    binds reactively; only reach for it if a specific player misbehaves.
    Per-app volume is a separate real capability —
    `Pipewire.nodes` includes stream nodes (`node.isStream`) with their
    own `audio.volume`/`audio.muted`, keyed by
    `properties["application.name"]` — see caelestia's `Audio.qml`
    `streams`/`getStreamVolume` (§1c).

---

## Evidence

### 1. Where the FFT comes from

**1a. DankMaterialShell — pure-QML `cava` subprocess, the direct template
for this repo.** `quickshell/Services/CavaService.qml`
([AvengeMedia/DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/Services/CavaService.qml)):

```qml
pragma Singleton
Singleton {
    id: root
    property list<int> values: Array(6)
    property int refCount: 0
    property bool cavaAvailable: false
    readonly property string _confPath: `${Paths.strip(StandardPaths.writableLocation(StandardPaths.TempLocation))}/dms-cava-${Date.now()}-${Math.floor(Math.random() * 1000000)}.conf`

    Process {
        // one-shot `command -v cava` on Component.onCompleted sets cavaAvailable
        // (also false if env DMS_DISABLE_CAVA=1)
    }

    Process {
        id: cavaProcess
        running: root.cavaAvailable && root.refCount > 0
        // command heredocs the same [general]/[output]/[smoothing] config shown
        // under RECOMMENDATION §1 to a temp path, then `exec cava -p <path>`
        command: ["sh", "-c", `cat <<'CAVACONF' > ${root._confPath}\n...\nCAVACONF\nexec cava -p ${root._confPath} < /dev/null`]

        onRunningChanged: if (!running) root.values = Array(6).fill(0);

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (root.refCount <= 0 || data.length === 0) return;
                const parts = data.split(";");
                if (parts.length < 6) return;
                const points = parts.slice(0, 6).map(p => parseInt(p, 10));
                if (points.every((v, i) => v === root.values[i])) return;
                root.values = points;
            }
        }
    }
}
```

The config is heredoc'd to a temp file and cava is invoked with `-p
<path>` — generate it at runtime rather than shipping/expecting a static
`~/.config/cava/config`, so the widget is self-contained and never
collides with a user's own cava setup. `running: root.cavaAvailable &&
root.refCount > 0` is the whole idle-CPU story: the `Process` doesn't
exist at all (no PID, no polling) unless something has incremented
`refCount`.

The ref-counting mechanism itself,
[`quickshell/Common/Ref.qml`](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/Common/Ref.qml):

```qml
import QtQuick
import Quickshell

QtObject {
    required property Singleton service
    property bool active: true
    property bool _held: false

    function sync(wanted) {
        if (wanted === _held) return;
        _held = wanted;
        service.refCount += wanted ? 1 : -1;
    }

    onActiveChanged: sync(active)
    Component.onCompleted: sync(active)
    Component.onDestruction: sync(false)
}
```

Consumed from the bar widget,
[`quickshell/Modules/DankBar/Widgets/AudioVisualization.qml`](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/Modules/DankBar/Widgets/AudioVisualization.qml):

```qml
readonly property bool live: visible && enabled && (Window.window?.visible ?? false) && isPlaying

Loader {
    active: root.live
    sourceComponent: Component { Ref { service: CavaService } }
}

Connections {
    target: CavaService
    enabled: root.live
    function onValuesChanged() { /* re-normalize CavaService.values into the bars */ }
}
```

i.e. the `Ref` only exists (and only holds the count) while the `Loader`
is `active`, gated on `live = visible && playing`. This is the
"kill/suspend cava when nothing plays" answer in concrete code: no manual
`Process.running = false` bookkeeping, just compose
`active`/`visible`/`enabled` booleans and let the singleton's `refCount`
sum them. (Rendering there is a `ShaderEffect` fed packed `vector4d`
bands — see §2 for why that's not recommended at this repo's scale.)

**1b. caelestia-dots/shell — the "went further" alternative: `cava` moved
into a compiled Quickshell plugin.**
[`plugin/src/Caelestia/Services/cavaprovider.cpp`/`.hpp`](https://github.com/caelestia-dots/shell/tree/main/plugin/src/Caelestia/Services)
expose a `CavaProvider` QML type that links `libcava` directly (no
subprocess, no text parsing) — see it wired into
[`services/Audio.qml`](https://github.com/caelestia-dots/shell/blob/main/services/Audio.qml):

```qml
CavaProvider {
    id: cava
    bars: GlobalConfig.services.visualiserBars
}
```

Consumed by a radial `QtQuick.Shapes` visualizer around the album art,
[`modules/dashboard/media/CoverVisualiser.qml`](https://github.com/caelestia-dots/shell/blob/main/modules/dashboard/media/CoverVisualiser.qml) —
worth knowing as a "fancier" reference for a future panel iteration (bars
arranged radially, `Audio.cava.values[modelData]` driving `PathLine`
endpoints via trig), but their bar-smoothing itself
(`VisualiserBars`/`visualiserbars.cpp`) was *also* moved into C++ —
caelestia's trajectory was subprocess-QML → compiled plugin as their
visualizer usage grew (multiple simultaneous instances, wallpaper-blur
compositing). Right call at their scope, not for a single bar widget here.

**1c. Does `Quickshell.Services.Pipewire` expose sample/spectrum data?**
No FFT/spectrum, but yes to real-time **peak** metering, natively, no
subprocess:
[`PwNodePeakMonitor`](https://github.com/quickshill-place/quickshell-mirror/blob/master/src/services/pipewire/peak.hpp)
(source: `quickshell-mirror/quickshell`, `src/services/pipewire/peak.hpp`):

```cpp
/// Monitors peak levels of an audio node. Tracks volume peaks across channels.
class PwNodePeakMonitor: public QObject {
    Q_PROPERTY(qs::service::pipewire::PwNodeIface* node READ node WRITE setNode NOTIFY nodeChanged);
    Q_PROPERTY(bool enabled READ isEnabled WRITE setEnabled NOTIFY enabledChanged);
    /// Per-channel peak noise levels (0.0-1.0). Length matches @@channels.
    Q_PROPERTY(QVector<float> peaks READ peaks NOTIFY peaksChanged);
    Q_PROPERTY(float peak READ peak NOTIFY peakChanged); // max of peaks
```

Real usage, [Gronoxx/RiceOs `shell/AudioModule.qml`](https://github.com/Gronoxx/RiceOs/blob/main/shell/AudioModule.qml):
`PwObjectTracker { objects: [Pipewire.defaultAudioSink] }` alongside
`PwNodePeakMonitor { node: Pipewire.defaultAudioSink; enabled: true }`,
then bind a bar's height to `peakMonitor.peak`.

This is a single scalar (or per-channel small vector) "how loud is this
node right now" — a real, free, native VU-meter primitive worth knowing
for a *simple* "pulse the icon with the beat" effect, but it cannot
produce the 6+ independently-moving frequency-band bars the spec asks
for; that still requires an actual FFT, i.e. `cava`. Every real multi-band
visualizer found in the ecosystem search (DankMaterialShell, caelestia,
and the other dotfiles repos surfaced by the `PwNodePeakMonitor` code
search) uses `cava` for the spectrum and reserves `PwNodePeakMonitor` for
plain volume/VU indicators (e.g. `HANCORE-linux/quickshell-dots`
`panels/MicrophonePeakMonitor.qml`).
Beyond metering, `Pipewire.nodes` otherwise only exposes node
identity/routing/volume/mute (confirmed by caelestia's `services/Audio.qml`,
which builds `sinks`/`sources`/`streams` lists purely from
`node.isSink`/`node.isStream`/`node.audio.volume`/`node.audio.muted` — no
sample buffers) — also the evidence for the per-app volume note in
Recommendation §10.

**CPU cost.** `cava` at `framerate=25`, reading via PipeWire's monitor
source and doing a real FFT, is well under 1% CPU on any x86 machine
including an Intel iGPU laptop — a decades-old, single-purpose C program
built for terminal spectrum visualizers on far weaker hardware. The real
cost lever isn't the FFT, it's whether the process runs *at all* when
nothing is playing — why the `refCount`/`sleep_timer` combination in
Recommendation §1-2 matters more than `framerate` tuning.

### 2. Rendering at ~30px

- **Repeater + Rectangle** (recommended for the compact bar segment, see
  Recommendation §3): plain scene-graph rectangles, `Behavior on height`
  per bar for inter-frame smoothing, cheapest to write and reason about at
  6 bars.
- **ShaderEffect** (DankMaterialShell, §1a above): fastest to paint at
  scale, needs a compiled `.qsb` shader shipped alongside the QML.
- **QtQuick.Shapes** (caelestia `CoverVisualiser`, §1b above): for a
  radial/curved arrangement (bars fanned around album art), not a
  straight bar row — keep in mind for a fancier future panel look, not
  the compact bar.
- **Canvas**: not used by any real example found; each frame is a full
  immediate-mode repaint outside the scene graph, strictly worse than
  animated `Rectangle`s for simple bars.
- **Smoothing between frames**: caelestia's background visualizer pairs
  its bars with a driving `FrameAnimation`
  (`modules/background/Visualiser.qml`): `FrameAnimation { running:
  root.opacity > 0 && !bars.settled; onTriggered: bars.advance(frameTime) }`
  — the *bars component* owns per-frame easing toward the latest cava
  values, decoupling "how often does cava emit new numbers" (25fps) from
  "how often does the UI redraw" (every compositor frame). At this repo's
  scale, a `Behavior on height { NumberAnimation {...} }` per `Rectangle`
  gets the same visual smoothing for a fraction of the code, with no
  `FrameAnimation` running unconditionally.
- **Stopping CPU burn when idle**: see Recommendation §1-2 and §1a's
  `Ref`/`refCount` code — the renderer only ever runs while `visible` and
  bound to live data anyway; the actual win is keeping `cava` itself from
  running.

### 3. Rich MPRIS panel

**3a. `position` does not auto-update — official Quickshell source doc,**
[`src/services/mpris/player.hpp`](https://github.com/quickshill-place/quickshell-mirror/blob/master/src/services/mpris/player.hpp)
(`quickshell-mirror/quickshell`):

```cpp
/// The current position in the playing track, as seconds, with millisecond
/// precision, or `0` if @@positionSupported is false.
/// May only be written to if @@canSeek and @@positionSupported are true.
///
/// > [!WARNING] To avoid excessive property updates wasting CPU while `position` is not
/// > actively monitored, `position` usually will not update reactively, unless a nonlinear
/// > change in position occurs, however reading it will always return the current position.
/// > If you want to actively monitor the position, the simplest way it to emit the @@positionChanged(s)
/// > signal manually for the duration you are monitoring it, using a @@QtQuick.FrameAnimation if you need
/// > the value to update smoothly, such as on a slider, or a @@QtQuick.Timer if not.
Q_PROPERTY(qreal position READ position WRITE setPosition NOTIFY positionChanged);
Q_PROPERTY(bool positionSupported READ positionSupported NOTIFY positionSupportedChanged);
Q_PROPERTY(qreal length READ length NOTIFY lengthChanged);
Q_PROPERTY(bool canSeek READ default NOTIFY canSeekChanged BINDABLE bindableCanSeek);
```

The doc comment then shows literally the two idioms used in Recommendation
§6 (a `FrameAnimation.onTriggered: player.positionChanged()` guarded on
`playbackState == Playing` for smooth sliders, or a 1000ms `Timer` doing
the same for plain numeric labels) — this is the primary source for that
recommendation, not an inference. The same header documents the other
`canX`/`xSupported` twins referenced throughout this document:
`canControl`, `canPlay`, `canPause`, `canTogglePlaying`, `canGoNext`,
`canGoPrevious`, `loopState`/`loopSupported` (enum `None=0, Track=1,
Playlist=2`), `shuffle`/`shuffleSupported`, with the explicit class-level
warning: *"Support for various functionality and general compliance to
the MPRIS specification varies wildly by player. Always check the
associated `canXyz` and `xyzSupported` properties if available."*

DankMaterialShell applies exactly this Timer idiom in its media tab,
[`quickshell/Modules/DankDash/MediaPlayerTab.qml`](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/Modules/DankDash/MediaPlayerTab.qml):
`Timer { interval: 1000; running: root.live && activePlayer?.playbackState
=== MprisPlaybackState.Playing && !isSeeking; repeat: true; onTriggered:
activePlayer?.positionChanged() }` — guarding on `!isSeeking` so a live
drag isn't fighting a 1-second correction from the player.

**3b. Album art — resolution + caching**, same file, `TrackArtService.qml`
(see Recommendation §5 for the trimmed-down version to actually build).
Its resolver falls back `trackArtUrl` → `metadata["mpris:artUrl"]` →
(YouTube-only) a derived thumbnail URL from the video id in
`metadata["xesam:url"]`, then branches on the resolved url: `http(s)://`
is downloaded once to a content-hashed cache path and `Image.source` is
repointed at the local `file://` copy; a `file://` url is polled briefly
for the file to land (cover art often arrives slightly after the
track-change signal) then also copied into a content-addressed cache
path so identical art across tracks/players reuses one file; an empty
url clears the art after a short debounce — confirming the three cases
named in the spec (`file://` used directly/hashed, `http(s)://` needing
a one-shot download since `Image` can't be trusted to cache a remote url
across track changes, and missing falling back to a placeholder rather
than a broken-image glyph).

**3c. Multi-player selection**, same file: `allPlayers:
MprisController.availablePlayers`, and a `cyclePlayer()` that filters
`allPlayers` to non-idle players, finds the current index, and calls
`MprisController.setActivePlayer(players[(currentIndex + 1) %
players.length])` — a simple cycle-through-active-players function; the
panel exposes this via a small button/icon row rather than a dropdown
(Recommendation §7).

**3d. Loop/shuffle**, same file: `cycleLoopState()` guards on
`activePlayer?.canControl && activePlayer.loopSupported`, then switches
`activePlayer.loopState` through `MprisLoopState.None → Playlist → Track →
None`; shuffle is a plain boolean toggle
(`activePlayer.shuffle = !activePlayer.shuffle`) gated the same way
(`canControl && shuffleSupported`).

**3e. Hover-hold timer.** The same file guards its player-switch button
with a restartable `_switchHoldTimer` rather than acting on the raw hover
signal — apply the same idea to the widget-hover → panel-hover handoff:
don't close on `exited` immediately, restart a short (150-250ms) close
timer and cancel it if the pointer re-enters either the trigger or the
panel.

### 4. playerctl vs native Mpris; per-app volume

Every real Quickshell shell surveyed (DankMaterialShell, caelestia,
RiceOs, and the other repos surfaced by the `PwNodePeakMonitor`/`cava`
searches) uses `Quickshell.Services.Mpris` directly, never shells out to
`playerctl` — it's reactive (property bindings + signals) instead of
poll-a-subprocess, and this repo's current `Media.qml` already uses it
correctly. Per-app volume, confirmed via caelestia's `services/Audio.qml`
(§1c): stream nodes (`Pipewire.nodes.values` filtered on
`node.isStream`) each carry their own `audio.volume`/`audio.muted`, keyed
by `node.properties["application.name"]` — the same `Pipewire`/
`PwObjectTracker` machinery already touched by `PwNodePeakMonitor` in §1c.

---

## Sources

- [AvengeMedia/DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) —
  `quickshell/Services/{CavaService,TrackArtService}.qml`,
  `quickshell/Common/Ref.qml`,
  `quickshell/Modules/DankBar/Widgets/AudioVisualization.qml`,
  `quickshell/Modules/DankDash/MediaPlayerTab.qml`
- [caelestia-dots/shell](https://github.com/caelestia-dots/shell) —
  `services/Audio.qml`,
  `modules/background/Visualiser.qml`,
  `modules/dashboard/media/CoverVisualiser.qml`,
  `plugin/src/Caelestia/Services/cavaprovider.{cpp,hpp}`,
  `plugin/src/Caelestia/Components/visualiserbars.{cpp,hpp}`
- [quickshell-mirror/quickshell](https://github.com/quickshill-place/quickshell-mirror) —
  `src/services/mpris/player.hpp` (official `MprisPlayer` API + `position`
  polling doc comment), `src/services/pipewire/peak.hpp` (`PwNodePeakMonitor`)
- [Gronoxx/RiceOs](https://github.com/Gronoxx/RiceOs) —
  `shell/AudioModule.qml` (`PwNodePeakMonitor` real-world usage)
- Local: `configs/quickshell/plugins/bar/widgets/Media.qml`,
  `configs/quickshell/plugins/wifiqr/manifest.json` and sibling
  `keepLoaded: true` manifests, `configs/quickshell/shell.qml` (Loader
  `active: panelEntry.sourceUrl !== "" && (panelEntry.keepLoaded ||
  shell.openPanelIds[...])`), `configs/quickshell/Commons/Color.qml`
