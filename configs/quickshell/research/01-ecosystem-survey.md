# Quickshell Ecosystem Survey (2026-09)

Purpose: survey what other Quickshell (QML) desktop-shell projects do better than
this repo's `configs/quickshell/` (~15k lines, originally a 1:1 port of Omarchy's
`omarchy-shell`), to inform growing it into a full DE.

Constraints baked into every recommendation below (do not suggest reverting
these): pywal-only theming, no multi-theme/Material-You layer; panels open on
**hover**, not click, and that's deliberate; persistent state changes go through
`toggles/toggle-*.sh` shell scripts, never QML writing config files directly;
Arch + Hyprland, single user; font pinned to "0xProto Nerd Font".

Baseline (what this repo already has, checked directly in
`configs/quickshell/`, so I don't recommend re-inventing it): singleton services
under `services/` (`AppLibrary.qml`, `BarWidgetRegistry.qml`, `PluginRegistry.qml`),
a `plugins/` directory (bar/background/lock/osd/notifications/clipboard/appsearch
each as a self-contained plugin), `IpcHandler` already used in `shell.qml`,
`plugins/bar/Bar.qml`, `plugins/osd/Osd.qml`, `plugins/notifications/Service.qml`,
`plugins/clipboard/Clipboard.qml`, `plugins/lock/Lock.qml`, `plugins/appsearch/AppSearch.qml`.
`Variants` already used for per-monitor bar/background instantiation. `ShaderEffect`
already used (`toggle-cyberpunk-shader.sh`). Imports already in use: `Quickshell`,
`Quickshell.Hyprland`, `Quickshell.Io`, `Quickshell.Services.{Mpris,Notifications,
Pam,Pipewire,SystemTray,UPower}`, `Quickshell.Wayland`. **Not** currently imported
anywhere: `Quickshell.Widgets`, `Quickshell.Bluetooth`, `Quickshell.Networking`,
`Quickshell.Services.Polkit`, `Quickshell.Services.Greetd`, `Quickshell.DBusMenu`.
Network/brightness/bluetooth are all done today via `Process` shell-outs
(`nmcli`/`brightnessctl`/etc. — grep hits in `Network.qml`, `Display.qml`,
`AudioIO.qml`, `System.qml`, `Battery.qml`, `Costs.qml`, `Weather.qml`,
`SystemUpdate.qml`, `KeyboardLayout.qml`, `News.qml`, `Agents.qml`, `Toggles.qml`,
`Clipboard.qml`, `Dnd.qml`, `Reminder.qml`, `StayAwake.qml`, `Background.qml`,
`Commons/Style.qml`).

---

## 1. caelestia-dots/shell

<https://github.com/caelestia-dots/shell>

The shell that end-4's illogical-impulse and much of the newer ecosystem (incl.
parts of noctalia's legacy QML tree) directly copy-and-credit code from
("Took many bits from caelestia-dots/shell (GPLv3)" appears verbatim in end-4's
`Network.qml` and `Brightness.qml`). Material-You/matugen theming (irrelevant
here given pywal-only), but the **architecture** is the most reusable part.

**Standout: it ships a native C++ Quickshell plugin, not just QML.**
`plugin/src/Caelestia/...` (CMake-built, `plugin/CMakeLists.txt`) contains hand
-written Qt/C++ types registered into a `Caelestia` QML import: blob/shader
shapes (`plugin/src/Caelestia/Blobs/blobmaterial.cpp`), a `LazyListView`
(`plugin/src/Caelestia/Components/lazylistview.cpp`), a `VisualiserBars` audio
spectrum widget (`plugin/src/Caelestia/Components/visualiserbars.cpp`), a
`SparklineItem`, and even a native network-usage sampler
(`plugin/src/Caelestia/Services/networkusage.cpp`) instead of parsing
`/proc/net/dev` in JS. This is a heavier lift than this repo needs today, but
it's the answer to "what do you do when QML-side polling/JS parsing gets too
slow" — worth knowing the escape hatch exists rather than fighting JS forever.

| Capability | File | QML/type used | Built-in vs subprocess |
|---|---|---|---|
| App launcher | `modules/launcher/services/Apps.qml`, `modules/launcher/AppList.qml` | `Quickshell.DesktopEntry` via custom `Searcher` base (`Caelestia.Models`); `Quickshell.execDetached` to launch | Built-in (DesktopEntry) + subprocess only for the actual exec |
| Wallpaper switcher | `services/Wallpapers.qml`, `modules/background/Wallpaper.qml`, `modules/launcher/items/WallpaperItem.qml` | Custom `Searcher`/`FileSystemEntry` model over the wallpaper dir; picking a wallpaper is a launcher result type (`WallpaperItem.qml`), not a separate panel | Subprocess to apply (calls out to their `caelestia` CLI / swww-style setter) |
| Lock screen | `modules/lock/Lock.qml`, `LockSurface.qml`, `Pam.qml`, `Center/PasswordInput.qml` | `Quickshell.Wayland.WlSessionLock` + `Quickshell.Services.Pam` (`PamContext`) directly in QML — no `pam_unix`/`su` subprocess | **Built-in** (`WlSessionLock` + native `Pam` service) |
| Bar | `modules/bar/Bar.qml`, `BarWrapper.qml`, per-icon `status/*.qml` | `PanelWindow` + `Variants` over `Quickshell.screens` | Built-in |
| Notifications | `modules/notifications/*.qml`, `services/Notifs.qml`, `NotifData.qml` | `Quickshell.Services.Notifications.NotificationServer` | Built-in |
| Clock/calendar | `modules/lock/center/Clock.qml`, `modules/background/DesktopClock.qml` | `Quickshell.SystemClock` on-lock and on-desktop (a literal analog/digital clock rendered on the wallpaper layer, not just the bar) | Built-in |
| Media | `services/Players.qml`, `modules/dashboard/media/CoverVisualiser.qml`, `LyricList.qml` | `Quickshell.Services.Mpris` + native `VisualiserBars`/cava-backed audio viz + **synced lyrics** display | Built-in Mpris; lyrics fetched via subprocess/HTTP |
| System stats | `modules/dashboard/performance/NetworkCard.qml` | native `networkusage.cpp` plugin type, not JS `/proc` parsing | Built-in (native plugin) |
| Network | `modules/bar/popouts/Network.qml`, `services/Nmcli.qml`, `utils/NetworkConnection.qml` | Plain QML `Singleton` wrapping `nmcli` via `Quickshell.Io.Process` | **Subprocess** (nmcli), even in this newest-generation shell |
| Audio | `services/Audio.qml` | `Quickshell.Services.Pipewire` (`Pipewire.defaultAudioSink/.audio.volume/.muted`) + a `cava` process for the visualiser only | Built-in for volume/mute; subprocess only for spectrum data |
| Display/brightness | `services/Brightness.qml` | `Quickshell.Io.Process` running `brightnessctl` **and** `ddcutil` (external monitors over DDC/CI), keyed per `ShellScreen` | Subprocess (both paths) |

Takeaway for this repo: the lock screen pattern (`WlSessionLock` + `Pam`
directly, no external `su`/`swaylock` binary) and the "wallpaper as a launcher
result type" pattern are both directly liftable without touching theming.

## 2. end-4/dots-hyprland ("illogical-impulse")

<https://github.com/end-4/dots-hyprland> — shell lives at
`dots/.config/quickshell/ii/`

The biggest single-repo feature surface of the four: **45+ singleton services**
under `services/` including things far outside a status bar's normal scope —
`Ai.qml` (chat sidebar with pluggable `ApiStrategy` backends: Gemini/Mistral/
OpenAI, `services/ai/*.qml`), `Booru.qml` (image board browser, irrelevant
here), `Todo.qml`, `Weather.qml`, `Translation.qml`, `Cliphist.qml`, `Emojis.qml`,
`SongRec.qml` (audio fingerprinting via subprocess), `KeyringStorage.qml`,
`FirstRunExperience.qml`, `SessionWarnings.qml`, `HyprlandAntiFlashbangShader.qml`
(a `ShaderEffect` that fades in on Hyprland reload/monitor plug so you don't get
a white flash), `HyprlandConfig.qml`/`HyprlandKeybinds.qml` (parses the user's
actual `hyprland.conf` to show live keybind cheatsheets in-shell).

| Capability | File | QML/type used | Built-in vs subprocess |
|---|---|---|---|
| App launcher | `services/LauncherApps.qml`, `services/LauncherSearch.qml`, `modules/ii/overview/*.qml` | `Quickshell.DesktopEntry` + fuzzy search index | Built-in |
| Wallpaper switcher | `services/Wallpapers.qml` | `Qt.labs.folderlistmodel.FolderListModel` for browsing; **explicitly documented** as "calls the existing `switchwall.sh` script" | **Subprocess by design** — the QML layer is just a picker UI, actual apply/colorgen goes through a shell script (directly analogous to this repo's `toggles/toggle-*.sh` convention) |
| Lock screen | `modules/common/panels/lock/LockScreen.qml`, `LockContext.qml` | `Quickshell.Wayland` session lock | Built-in |
| Bar | `modules/ii/bar/Bar.qml`, `BarContent.qml`, `BarGroup.qml` | `PanelWindow` + grouped "pill" widgets | Built-in |
| Notifications | `modules/common/widgets/Notification*.qml`, `services/Notifications.qml` | `Quickshell.Services.Notifications`, with **grouping by app** (`NotificationGroup.qml`) and expand/collapse | Built-in |
| Clock/calendar | `modules/ii/background/widgets/clock/*.qml` | A full **analog clock rendered on the desktop background** (`HourHand.qml`/`MinuteHand.qml`/`SecondHand.qml`/`MinuteMarks.qml`) plus a digital variant and date-indicator styles (bubble/rotating/rectangle) — clock is a first-class desktop widget, not just a bar item | Built-in (`Quickshell.SystemClock`) |
| Media | `services/MprisController.qml`, `modules/ii/bar/Media.qml` | `Quickshell.Services.Mpris` | Built-in |
| System stats | `services/ResourceUsage.qml`, `SystemInfo.qml` | JS parsing of `/proc`/`/sys` via `Quickshell.Io.FileView` (not raw `Process` spawn — reads files directly, cheaper than shelling to `top`/`free`) | **Built-in-ish**: still a shell-out-free read path, distinct from spawning a subprocess each tick |
| Network | `services/Network.qml`, `services/network/WifiAccessPoint.qml` | QML `Singleton` around `nmcli` (comment: *"Took many bits from caelestia-dots/shell"*) | Subprocess (nmcli) |
| Audio | `services/Audio.qml`, `EasyEffects.qml` | `Quickshell.Services.Pipewire` + optional EasyEffects preset control | Built-in, with subprocess only for EasyEffects presets |
| Display/brightness | `services/Brightness.qml` | `brightnessctl`/`ddcutil` via `Process` (ported from caelestia) | Subprocess |
| Bonus: night light | `services/Hyprsunset.qml` | wraps `hyprsunset` binary | Subprocess |
| Bonus: polkit agent | `services/PolkitService.qml` | **`Quickshell.Services.Polkit`** (`PolkitAgent`/`flow`) | **Built-in** — this repo uses the KDE agent instead, by explicit choice; porting is a theming win only (see §corrections) |
| Bonus: idle/lock policy | `services/Idle.qml` | `Quickshell.Wayland` idle inhibitor, tied into a `Persistent` settings singleton | Built-in |

Takeaway: the "clock as a desktop widget, not a bar widget" pattern and the
"parse `hyprland.conf` for a live keybind cheatsheet" pattern are both cheap,
high-payoff, and orthogonal to theming. The `Quickshell.Services.Polkit` agent
is the single most valuable missing built-in for turning this into a "full DE"
— right now there's presumably no in-shell GUI auth prompt for privileged
actions (pkexec-triggered GUI operations, `virt-manager`, etc. fall back to a
generic system polkit agent or none at all).

## 3. noctalia-dev/noctalia-shell

<https://github.com/noctalia-dev/noctalia-shell>

**Important finding for the "note API churn" requirement**: the `main` branch
of this repo is **no longer Quickshell**. Noctalia v5 (currently beta, tags
`v5.0.0-beta.1`…`v5.0.0-beta.10`) was rewritten from scratch as "a native
Wayland desktop shell... built directly on Wayland and OpenGL ES with **no Qt
or GTK dependency**" (repo README, confirmed by `.clang-format`/`.clang-tidy`/
`meson.build`/pure C++ tree on `main`, zero `.qml` files). The QML/Quickshell
version lives on the **`legacy-v4`** branch (tags `v4.7.7` and earlier) and is
what's surveyed below. This is a real, first-hand data point that at least one
serious Quickshell shell author concluded QML/Quickshell wasn't worth staying
on long-term for a polished full-DE product — worth being aware of, not
necessarily worth acting on for a personal single-user dotfiles repo where the
QML approach's iteration speed matters more than raw perf/packaging.

`legacy-v4` structure (`Modules/`, `Services/`) is the cleanest-organized of
the four surveyed — services are grouped by domain
(`Services/Compositor/`, `Services/Hardware/`, `Services/Keyboard/`,
`Services/Location/`, `Services/Media/`, `Services/Networking/`,
`Services/Power/`, `Services/System/`) rather than one flat directory, and it
explicitly abstracts the compositor: `Services/Compositor/{HyprlandService,
NiriService,SwayService,LabwcService,MangoService,ExtWorkspaceService}.qml`
behind one `CompositorService.qml` interface (irrelevant to a Hyprland-only
repo, but the *domain-grouped services folder* is a good organizing idea even
single-compositor).

| Capability | File (legacy-v4) | QML/type used | Built-in vs subprocess |
|---|---|---|---|
| App launcher | `Modules/Panels/Launcher/Launcher.qml`, `LauncherCore.qml`, `Providers/*.qml` | **Pluggable provider architecture**: `ApplicationsProvider.qml`, `CalculatorProvider.qml`, `ClipboardProvider.qml`, `CommandProvider.qml`, `EmojiProvider.qml`, `SessionProvider.qml`, `SettingsProvider.qml`, `WindowsProvider.qml` each register as a launcher result source | Built-in (DesktopEntry) for apps, subprocess for clipboard/session actions |
| Wallpaper switcher | `Modules/Bar/Widgets/WallpaperSelector.qml`, `Panels/ControlCenter/Widgets/WallpaperSelector.qml` | picker UI over a directory model | Subprocess to apply |
| Lock screen | `Modules/LockScreen/LockScreen.qml`, `LockContext.qml`, `LockScreenBackground.qml` | `Quickshell.Wayland` session lock, separate `LockScreenPanel.qml`/`LockScreenHeader.qml` for layout | Built-in |
| Bar | `Modules/Bar/Bar.qml`, `Extras/BarPill*.qml` | pill-shaped grouped widgets, per-widget `BarWidgetLoader.qml` (lazy `Loader`) | Built-in |
| Notifications | `Modules/Notification/Notification.qml`, `Panels/ControlCenter/Widgets/Notifications.qml` | `Quickshell.Services.Notifications` | Built-in |
| Clock/calendar | `Modules/Panels/Clock/ClockPanel.qml`, `DesktopWidgets/Widgets/DesktopClock.qml`, `Services/Location/CalendarService.qml`, `Services/Location/Calendar/{EvolutionDataServer,Khal}.qml` | Real calendar backends — EDS (Evolution Data Server, GNOME/Thunderbird calendars) and `khal` (CLI calendar) as pluggable calendar sources | Subprocess (khal) / DBus (EDS) |
| Media | `Modules/Cards/MediaCard.qml`, `Services/Media/MediaService.qml`, `SpectrumService.qml` | `Quickshell.Services.Mpris` + spectrum analyzer | Built-in + subprocess for spectrum |
| System stats | `Modules/Bar/Widgets/SystemMonitor.qml`, `NoctaliaPerformance.qml` | — | mixed |
| Network | `Services/Networking/NetworkService.qml` | **`import Quickshell.Networking`** — the native NetworkManager QML module (see docs section below) | **Built-in** — this is the only one of the four repos using Quickshell's native network module instead of shelling out to `nmcli` |
| Bluetooth | `Services/Networking/BluetoothService.qml`, `BluetoothRssi.qml` | subprocess-based (predates Quickshell's native `Quickshell.Bluetooth`, which is newer) | Subprocess |
| Audio | `Services/Media/AudioService.qml` | `Quickshell.Services.Pipewire` | Built-in |
| Display/brightness | `Services/Hardware/BrightnessService.qml` | `brightnessctl`/ddc via `Process`, keyed per `Monitor` model | Subprocess |
| Bonus: IPC/hooks | `Services/Control/IPCService.qml`, `HooksService.qml`, `CustomButtonIPCService.qml` | `IpcHandler` + a **hook system**: `HooksService.qml` listens for state changes (e.g. dark-mode toggle) via `Connections { target: Settings.data... }` and then runs a user-defined external script — i.e. "run this script when X changes" as a first-class, user-configurable feature | Subprocess (the hook script itself), triggered by built-in QML property watching |

Takeaway: the `HooksService.qml` pattern — QML watches a `Settings`/state
singleton and *fires an external script on change* — is architecturally
identical to this repo's `toggles/toggle-*.sh` convention, just generalized
into "any state change can have a user script attached," and it's the
strongest single pattern to steal for extending the toggle system without
QML ever writing config files itself.

## 4. AvengeMedia/DankMaterialShell

<https://github.com/AvengeMedia/DankMaterialShell> — shell lives at
`quickshell/`

The most "productized" of the four: it ships a companion Go CLI (`core/` —
`core/internal/qsipc/client.go`) that talks to the running shell over
Quickshell's IPC (`docs/IPC.md`, `scripts/benchmark-ipc.sh`,
`quickshell/DMSShellIPC.qml`), and it has an actual third-party **plugin API**
with a scaffold generator: `.agents/skills/dms-plugin-dev/` (an AI-agent skill
for *writing* DMS plugins), `quickshell/PLUGINS/ExampleDesktopClock/` (a
working example plugin: `DesktopClock.qml` + `DesktopClockSettings.qml`),
`Services/PluginService.qml`, `Services/DesktopWidgetRegistry.qml`. This repo
already has an equivalent shape (`services/PluginRegistry.qml`,
`plugins/*`), so the validation here is "your existing plugin-directory
approach is the right shape, DMS just also ships a settings-UI generator and
a template for it."

| Capability | File | QML/type used | Built-in vs subprocess |
|---|---|---|---|
| App launcher | `Modules/DankLauncherV2/*.qml` (Controller, ResultsList, Section, SpotlightResultsList) | multiple launcher *layouts* (grid/list/spotlight/island) sharing one `Controller.qml` | Built-in |
| Wallpaper switcher | `Services/WallpaperCyclingService.qml`, `Modules/DankDash/WallpaperTab.qml`, `Modules/BlurredWallpaperBackground.qml`/`BlurredWallpaperLive.qml` | a **timer-driven auto-rotation service** as a first-class singleton (not just an on-demand picker), plus a live-blurred variant of the current wallpaper reused as a panel/lockscreen backdrop | Subprocess to apply; blur backdrop is a `ShaderEffect`, built-in |
| Lock screen | `Modules/Lock/Lock.qml`, `LockSurface.qml`, `Pam.qml`, `FadeToLockWindow.qml`, `FadeToDpmsWindow.qml`, `VideoScreensaver.qml` | `Quickshell.Wayland` + `Pam`, with a dedicated **fade transition window** shown while the real lock surface spins up (so there's no black flash), and optional video-file screensaver playback | Built-in, with polish (fade window) worth copying |
| Bar | `Modules/DankBar/DankBar.qml`, `WidgetHost.qml`, `BarCanvas.qml`, `DankBarHoverController.qml` | widgets are hosted via a generic `WidgetHost.qml` that loads widget QML by string id from settings (data-driven bar composition, not hardcoded imports); `DankBarHoverController.qml` is a dedicated hover-state manager | Built-in |
| Notifications | `Modules/Notifications` + `Services/NotificationService.qml`, `Modals/NotificationModal.qml` | `Quickshell.Services.Notifications` | Built-in |
| Clock/calendar | `Modules/DankBar/Widgets/Clock.qml`, `DankDash/Overview/{ClockCard,CalendarOverviewCard,CalendarEventDetail,CalendarEventEditor}.qml`, `Services/CalendarDankBackend.qml` | full calendar with event creation/editing, not just a read-only month view | Backend via subprocess/DBus |
| Media | `Modules/DankBar/Widgets/Media.qml`, `Services/MprisController.qml`, `TrackArtService.qml`, `AppleMusicArtService.qml`, `MediaAccentService.qml` | `Quickshell.Services.Mpris` + **derives an accent color from album art** (`MediaAccentService.qml`) to tint the media popout | Built-in Mpris; art-color extraction likely built-in `ColorQuantizer` (see docs section) |
| System stats | `Modules/DankBar/Widgets/{CpuMonitor,CpuTemperature,GpuTemperature,DiskUsage}.qml`, `Services/DgopService.qml` | `DgopService.qml` wraps an external stats-gathering helper (`dgop`, their own companion tool) rather than parsing `/proc` in JS themselves | Subprocess (their own Go helper binary, `dgop`) |
| Network | `Services/NetworkService.qml`, `Modals/{NetworkInfoModal,NetworkWiredInfoModal}.qml` | — | Subprocess (nmcli-based, pre-dates `Quickshell.Networking`) |
| Audio | `Services/AudioService.qml`, `AudioSoundPlayers.qml` | `Quickshell.Services.Pipewire` | Built-in |
| Display/brightness | `Services/DisplayService.qml`, `Modules/ControlCenter/Details/BrightnessDetail.qml` | `brightnessctl`/ddc | Subprocess |
| Bonus: greeter/login | `Services/GreeterService.qml`, `GreeterUsersService.qml` | **`Quickshell.Services.Greetd`** — DMS can run as an actual greetd-based login-manager UI, not just a lock screen | Built-in |
| Bonus: polkit | `Services/PolkitService.qml`, `PolkitAgentInstance.qml` | `Quickshell.Services.Polkit` | Built-in |
| Bonus: blur | `Services/BlurService.qml` | compositor-blur-aware `ShaderEffect` backdrop, with a fallback path when the compositor doesn't support real blur (`compositorSupported` flag) | Built-in (shader), with capability detection |

Takeaway: `WidgetHost.qml`'s "load bar widgets by string id from a settings
list" is the cleanest data-driven-bar pattern seen across all four repos, and
the fade-transition lock window plus blur-with-capability-detection are both
small, self-contained polish items with no theming implications.

---

## 5. Quickshell official docs — module/type surface

<https://quickshell.org/docs/types/> (redirected from the old
`quickshell.outfoxxed.me` domain — the project moved domains, another small
signal of how fast-moving/pre-1.0 this ecosystem is).

**Version churn is real and recent.** The docs site's default/cached snapshot
resolves to `v0.1.0`, but the actual latest release tag on
`quickshell-mirror/quickshell` is **`v0.3.1`** (`v0.1.0 → v0.2.0 → v0.2.1 →
v0.3.0 → v0.3.1`). Comparing the stale `v0.1.0` docs tree against the current
`master` source tree (`src/`) shows entire modules added since: **Bluetooth**,
**Networking**, and **`Quickshell.Services.Polkit`** did not exist in `v0.1.0`
and are absent from the cached docs page, but are real, shipping modules on
current `master`. Treat any specific property/signal name below as "check the
version actually installed" — this is not a stable API yet.

**Full type inventory as of the crawled `v0.1.0` docs page**, plus what's on
current source but missing from that snapshot (marked *NEW*):

- **`Quickshell` (top-level)**: `ShellRoot`, `PanelWindow`, `FloatingWindow`,
  `PopupWindow`, `Scope`, `Singleton`, `Variants`, `LazyLoader`,
  `PersistentProperties`, `Reloadable`, `Retainable`/`RetainableLock`,
  `ShellScreen`, `QsWindow`, `SystemClock`, `ElapsedTimer`,
  `DesktopEntry`/`DesktopEntries`/`DesktopAction`, `ObjectModel`,
  `ObjectRepeater`, `ScriptModel`, `ColorQuantizer` (extracts a palette from an
  image — directly relevant to "derive an accent from album art / wallpaper"
  without a subprocess), `BoundComponent`, `Region`/`RegionShape`/`Intersection`
  (for input-region shaping, e.g. click-through panels), `Edges`,
  `ExclusionMode`, `PopupAnchor`/`PopupAdjustment`, `QsMenuAnchor`/
  `QsMenuEntry`/`QsMenuHandle`/`QsMenuOpener`/`QsMenuButtonType` (native
  DBusMenu-driven context menus), `TransformWatcher`, `EasingCurve`,
  `QuickshellSettings`.
- **`Quickshell.Io`**: `Process`, `FileView`/`FileViewAdapter`/
  `FileViewError`, `JsonAdapter`/`JsonObject`, `IpcHandler`, `Socket`/
  `SocketServer`, `DataStream`/`DataStreamParser`/`SplitParser`,
  `StdioCollector`.
- **`Quickshell.Widgets`**: `IconImage` (theme-aware icon loading —
  **not currently imported anywhere in this repo**, worth checking whether
  icon rendering is hand-rolled), `ClippingRectangle`/
  `ClippingWrapperRectangle`, `WrapperItem`/`WrapperManager`,
  `MarginWrapperManager`.
- **`Quickshell.Wayland`**: `WlSessionLock`/`WlSessionLockSurface`,
  `WlrLayershell`, `WlrLayer`, `WlrKeyboardFocus`, `Toplevel`/
  `ToplevelManager`, `ScreencopyView` (screen capture — relevant for a
  screenshot/screen-recording widget without shelling to `grim`/`slurp`).
- **`Quickshell.Hyprland`**: `Hyprland`, `HyprlandMonitor`, `HyprlandWorkspace`,
  `HyprlandWindow`, `HyprlandEvent`, `HyprlandFocusGrab`, `GlobalShortcut`.
- **`Quickshell.Services.Mpris`**, **`.Notifications`**, **`.Pam`**,
  **`.Pipewire`**, **`.SystemTray`**, **`.UPower`**, **`.Greetd`** — all
  present in `v0.1.0`, all already used here except Greetd.
- **`Quickshell.DBusMenu`** — present in `v0.1.0`, unused here; feeds
  `QsMenuOpener` for native app/tray context menus instead of hand-rolled
  popup menus.
- **NEW since `v0.1.0` (confirmed via `quickshell-mirror/quickshell` `src/`
  tree, not yet reflected in the cached docs)**:
  - `Quickshell.Bluetooth` — `src/bluetooth/{bluez,adapter,device}.cpp`,
    singleton `Quickshell.Bluetooth.Bluetooth`, BlueZ DBus-backed. Nothing
    surveyed above uses it yet either (all four repos still shell out to
    `bluetoothctl`/nmcli-adjacent tools for Bluetooth) — this repo would be
    an early adopter, not behind the curve, if it picked this up.
  - `Quickshell.Networking` — `src/network/{network,device,wifi,wired,enums}.cpp`
    + `src/network/nm/` (NetworkManager backend), singleton
    `Quickshell.Networking.Networking`. **noctalia's `legacy-v4` is the only
    surveyed repo already using it**; everyone else still runs `nmcli`.
  - `Quickshell.Services.Polkit` — `src/services/polkit/` — `PolkitAgent`,
    `AuthFlow`, used by end-4 and DankMaterialShell already (see above).

## 6. Cross-cutting patterns worth stealing

- **Singleton service layer, one file per domain.** All four repos converge
  on the same shape this repo already has: a `pragma Singleton` QML object per
  external system (audio, network, brightness, mpris...), imported by id
  everywhere else. noctalia's `legacy-v4` is the best-organized variant —
  services are grouped into subfolders by domain (`Services/Hardware/`,
  `Services/Media/`, `Services/Power/`...) instead of one flat directory once
  the count gets past ~15-20 files. Worth doing here once `services/` grows
  past its current 5 files.

- **IPC handlers already used here — extend, don't introduce.** This repo
  already has `IpcHandler` wired into `shell.qml` and several plugins. The
  generalizable idea from noctalia's `HooksService.qml` is to let *any*
  watched state change (not just the ones that already have a handler)
  trigger `toggles/toggle-*.sh` — i.e. a small `Connections { target: <state
  singleton> }` block that shells out on change, so new toggles compose with
  existing state instead of each toggle inventing its own wiring.

- **Per-monitor `Variants`, already used.** All four repos and this repo use
  `Variants { model: Quickshell.screens }` (or `Hyprland.monitors`) to
  instantiate one `PanelWindow` per output. No gap here.

- **Lazy loading.** `Quickshell.LazyLoader` (top-level type, distinct from
  QtQuick's `Loader`) and plain `Loader { asynchronous: true }` show up
  repeatedly for panels/popouts that are hidden most of the time (caelestia's
  `modules/lock/Lock.qml` loads its content lazily; DMS's
  `Modules/Bar/Extras/BarWidgetLoader.qml` loads each bar widget lazily;
  noctalia's `BarWidgetLoader.qml` does the same). Given this repo's hover
  -driven panels open/close constantly, auditing whether every `HoverPanel`
  consumer uses `asynchronous: true` loading (vs. eagerly instantiating
  heavy content that only shows on hover) is a concrete, theming-agnostic
  perf check.

- **Animation idioms.** Spring/physics-based motion (`SpringMotion`-style
  helpers, seen as `Common/SpringMotion.qml` in DMS) is now more common than
  plain `NumberAnimation`/`Behavior on x` for panel open/close — it self
  -corrects if a hover-triggered animation gets interrupted mid-flight
  (relevant here specifically *because* panels are hover-driven and get
  interrupted by fast mouse movement constantly). Worth checking whether
  `Ui/HoverPanel.qml` uses interruption-safe animations today.

- **Shader/blur backdrops behind panels**, gated by compositor capability
  detection rather than assumed-on. DMS's `Services/BlurService.qml` exposes
  `compositorSupported`/`available` so the shader path degrades gracefully
  instead of erroring on compositors/GPU drivers without blur support. This
  repo already has one `ShaderEffect` (`toggle-cyberpunk-shader.sh`); the
  capability-flag pattern is reusable for a subtler always-on panel-backdrop
  blur without a toggle if desired.

- **Plugin/widget registries, already present here.** DMS's `PluginService.qml`
  + `DesktopWidgetRegistry.qml` + `.agents/skills/dms-plugin-dev/` (a
  scaffold-generator skill) is the most fleshed-out version of what this repo
  already does with `services/PluginRegistry.qml` + `plugins/`. The delta
  worth considering is DMS's convention of pairing every plugin widget with a
  co-located `*Settings.qml` (see `PLUGINS/ExampleDesktopClock/{DesktopClock,
  DesktopClockSettings}.qml`) — a per-plugin settings panel contract, not a
  new persistence mechanism (settings still round-trip through scripts here,
  per this repo's constraints).

## 7. What this shell probably isn't using yet (concrete gap list)

Ranked roughly by payoff-for-effort given the "grow into a full DE" goal and
the pywal/hover/toggle-script constraints:

1. **`Quickshell.Services.Polkit`** — *corrected after verification.* The
   original draft of this doc called this "the single most 'full DE'-defining
   missing piece" and said there is "no polkit agent at all today." **That is
   wrong.** There is no `Polkit` import inside `configs/quickshell/`, but a
   polkit agent *is* running and *is* deliberately configured:
   `polkit-kde-authentication-agent-1` is live (PID confirmed) and launched
   from `configs/hyprland/hyprland_autostart.lua:11` via
   `uwsm app -- /usr/lib/polkit-kde-authentication-agent-1`. TODO.md's Phase
   5 notes record this as an explicit decision: "Polkit kept as the existing
   KDE agent, not ported."

   So this is a **stylistic** gap, not a functional one: privilege prompts
   work, they just render in KDE chrome rather than pywal-themed shell
   chrome. Porting it to `Quickshell.Services.Polkit` (~1 QML singleton
   around `PolkitAgent`, as end-4 and DMS do) buys visual consistency, and
   should be ranked on that basis — not as a missing capability. Lower
   priority than this doc originally implied.
2. **`Quickshell.Networking`** — replaces the current `nmcli`-via-`Process`
   pattern (used in `plugins/bar/widgets/Network.qml` per the earlier grep)
   with a native DBus/NetworkManager binding: no process-spawn latency per
   scan/toggle, structured signals instead of parsing `nmcli` text output.
   Only noctalia's legacy branch has adopted this so far — low risk of being
   "behind," genuine opportunity to be ahead of caelestia/end-4/DMS here.
3. **`Quickshell.Bluetooth`** — same story; nobody surveyed uses it yet
   (all four still shell to `bluetoothctl`-equivalent). If this repo doesn't
   have a Bluetooth widget at all today, this is a "build it right the first
   time" opportunity rather than a migration.
4. **`Quickshell.Widgets.IconImage`** — not imported anywhere; if app/tray
   icons are currently resolved by hand-building icon-theme paths in JS, this
   built-in theme-aware icon loader is a direct, low-risk swap.
5. **`Quickshell.ColorQuantizer`** — palette extraction from an image, built
   -in. Not a theming-system replacement (pywal already owns that), but
   relevant if any widget wants a one-off accent color from album art or the
   current wallpaper (DMS's `MediaAccentService.qml` pattern) without
   shelling out to `imagemagick`/pywal a second time.
6. **`Quickshell.DBusMenu`/`QsMenuOpener`** — for tray-item and app
   right-click context menus, if those are currently hand-rolled popups
   instead of using the app/tray's actual DBusMenu.
7. **Desktop-anchored widgets (clock, media, audio-viz) placed directly on
   the wallpaper layer, not just the bar** — an architectural pattern (see
   end-4's `background/widgets/clock/` and DMS's `BuiltinDesktopPlugins/`),
   not a new Quickshell module. Straightforward to add as a new `plugins/`
   entry rendered by the existing `Background.qml` layer instead of the bar.
8. **`Quickshell.Wayland.ScreencopyView`** — built-in screen capture, if
   screenshot/region-select functionality doesn't exist yet or currently
   shells out to `grim`/`slurp`/`hyprshot`.
9. **`Quickshell.Services.Greetd`** — only relevant if this box ever runs a
   greetd-based login manager; skip unless that's actually the login flow
   (out of scope for "single user, personal Arch box" unless already the
   case).

**Do not adopt without a stronger reason**: caelestia's native C++ plugin
(`plugin/`) — real perf wins but a much bigger maintenance surface (CMake
build step, Qt/C++ toolchain in the repo) than a personal dotfiles repo
warrants unless a specific widget is provably JS-bottlenecked; multi
-backend/multi-compositor abstraction (noctalia's `CompositorService.qml`
family) — pure overhead for a Hyprland-only, single-user setup.

---

## Sources

- <https://github.com/caelestia-dots/shell>
- <https://github.com/end-4/dots-hyprland> (shell: `dots/.config/quickshell/ii/`)
- <https://github.com/noctalia-dev/noctalia-shell> (`main` = v5 C++ rewrite;
  `legacy-v4` branch = the QML/Quickshell version surveyed here;
  <https://noctalia.dev/ethos>, <https://docs.noctalia.dev>)
- <https://github.com/AvengeMedia/DankMaterialShell>
- <https://quickshell.org/docs/types/> (redirects from
  `quickshell.outfoxxed.me`; cached snapshot resolves to `v0.1.0`)
- <https://github.com/quickshell-mirror/quickshell> (source of truth for
  current module surface; latest tag at time of writing: `v0.3.1`)
