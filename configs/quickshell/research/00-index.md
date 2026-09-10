# quickshell DE research — index

Research backing the SPEC in `prompts.md`: *"we essentially want to build a
DE using Quickshell."* Written 2026-09-01.

Ten documents. Six (01, 03, 04, 05, 06, 08) are web research into how other
Quickshell shells solve each problem; two (02, 07) are local audits of this
repo; `ROADMAP.md` is the plan built from all of them.

**If you are here to work, go straight to `ROADMAP.md`.** It is the
sequenced implementation plan, and it also carries the port history and the
permanent gotchas that used to live in the repo's `TODO.md`. Everything
below is its reference material. **If you are here to understand the gap,
start with 07.**

A sibling doc, `ryoku-patterns.md`, is outside this numbered sequence — it's
a style-inspiration survey of a third-party Hyprland+Quickshell shell
(Ryoku), not SPEC gap-closing. Nothing in it has been applied here.

Another sibling, `pywal-wallust-migration.md`, is a full plan for replacing
pywal with wallust across every themed surface in this repo (Discord,
Firefox, Spotify, KDE/Qt, GTK, terminals, editors, and the bar). It directly
conflicts with Ground rule #3 below and this doc's own "pywal-only"
convention (§ Conventions) until/unless it's actually adopted — read its
own opening note before assuming either doc is still authoritative.

## Read in this order

| # | Doc | What it answers |
| --- | --- | --- |
| **★** | `ROADMAP.md` | **The plan.** 14 dependency-ordered phases, what's already done, a "what quickshell ends up replacing" scorecard, a **"Beyond quickshell"** section for desktop pieces it *cannot* own (portals, Qt theming, keyring, greeter), out-of-scope items, open decisions, plus Appendix A (permanent gotchas) and Appendix B (port history). |
| **07** | `07-spec-conformance.md` | **The spine.** Every SPEC bullet → what exists today → what the actual gap is. Read first; the others explain *how* to close what this one identifies. |
| **02** | `02-toggle-contract.md` | Which settings must go through `toggles/`, the four current violations, and the missing idiom for value-carrying settings. Answers the SPEC's "not just hacked together" clause. |
| 01 | `01-ecosystem-survey.md` | What caelestia, end-4, Noctalia, and DankMaterialShell do better, plus the Quickshell API surface and its pre-1.0 churn. |
| 03 | `03-media-visualizer.md` | The biggest gap: cava→QML spectrum bars and a rich MPRIS panel. |
| 04 | `04-system-sensors.md` | What this ThinkPad can and cannot report, including two honest "not possible" answers. |
| 05 | `05-network-tunnels.md` | Connectivity, bluetooth, localsend, and a safe offline mode. |
| 06 | `06-launcher-lock-wallpaper-and-cool-things.md` | Wallpaper switcher, launcher, lock screen, multi-monitor — and §5, the answer to "any other REALLY cool things?" |
| 08 | `08-weather.md` | Provider choice and the location strategy for "use the current location but NOT REVEAL IT". |

## The findings that change what you build

**Settled by the owner (2026-09-01)** — build to these, they are not open:

1. **Weather location:** GeoClue2 → manual coarse → timezone-derived, with
   coordinates rounded to ~2dp (≈1.1km) before any network call, and nothing
   location-identifying rendered in the panel.
2. **Font:** split `Style.font.ui` (all 4174 families, user-selectable) from
   `Style.font.icon` (pinned to `0xProto Nerd Font`). The glyph call-site
   sweep lands *before* the picker ships.
3. **Bar widgets:** `active-window`, `agents`, `microphone`, `news`, and
   `costs` dropped; `toggles` kept. Done — their `.qml` and manifests remain
   on disk, so re-adding any is one array entry.
4. **Decommission**, with status: `waybar` ✅ and `mako` ✅ removed;
   `walker` **blocked** (see below); `hyprlock` waits on lock-screen
   verification; `hypridle` waits on that *and* on a native idle chain
   (Phase 9b); `wlogout` waits on a native power menu (Phase 9c);
   `awww`/`swww` retired once the QML crossfade owns wallpaper (Phase 8).
   **pywal is not replaced** — it still generates the palette quickshell
   reads. Full scorecard in `ROADMAP.md` under the dependency graph.

**Corrections made while researching** — each of these was believed
otherwise at some point in this pass, so they are recorded rather than
quietly fixed:

- **`shell.qml` is not the source of truth for the bar layout.**
  `~/.local/state/quickshell/shell.json` overrides it. An earlier draft of
  doc 07 wrongly reported the system tray and battery as "never placed";
  both were live the whole time. The real issue is that the tracked builtin
  defaults are stale. (07 §0a)
- **Polkit is not a gap.** Doc 01 originally called it the single biggest
  missing piece; `polkit-kde-authentication-agent-1` is running and is
  deliberately configured in `hyprland_autostart.lua:11`. Porting it is a
  theming win only. (01)
- **`intel_gpu_top` is installed** — `system-stats.sh`'s comment says
  otherwise. The real blocker is `perf_event_paranoid=2`. (04)

**Live defects found and verified during the audit:**

- **Offline mode silently no-ops on Ethernet.** `rfkill` governs only
  radios; `rfkill list` here shows just WiFi and Bluetooth while
  `enp0s31f6` exists. The toggle reports success and leaves you online —
  the worst failure mode for a feature that exists to guarantee the
  opposite. (02 §5b, 05 §5)
- **mako was hijacking the notification bus.** `fr.emersion.mako.service`
  declared `Name=org.freedesktop.Notifications` for D-Bus activation, so
  mako auto-started on the first notification of every boot and won the
  race — regardless of its disabled systemd unit and its removal from
  hyprland autostart. Quickshell's daemon had therefore *never* been the
  live handler. Fixed by removing the package. **Note
  `/usr/share/dbus-1/services/org.kde.plasma.Notifications.service` still
  declares the same name** and could race the same way if plasma's
  notifier is ever installed.
- **`Ui/PanelSlider.qml` used `bar.foreground`**, which does not exist —
  `Bar.qml:50` exposes `barForeground`. Three properties silently resolved
  to undefined. Fixed. This was the *third* occurrence of this exact naming
  mismatch; `Tray.qml:25` already carries a warning comment about it.
- **`Osd.qml` pops on every monitor** rather than the focused one. (06 §4)
- **Two wallpaper renderers run at once** — `awww-daemon` alongside
  quickshell's own QML crossfade. (06 §1)

**Blocked, needs a decision:**

- **`walker` cannot be removed yet.** It has five live call sites, and the
  critical one is `hyprland_keybindings.lua:16`: **`Super+D` still opens
  walker**, and quickshell's app launcher has *no keybind at all*. Removing
  walker today would leave no keyboard launcher. Also used by
  `toggles/menu.sh` (the default non-fzf picker), `scripts/spawn-shimoji.sh`,
  `scripts/switch-wallpaper.sh` (themes walker's CSS), and
  `hyprland_autostart.lua:22`. "App Menu (replacing walker)" is materially
  incomplete until `Super+D` is rebound.

**Unblocked, do it before the next lock-screen attempt:**

- **Set Hyprland `misc:allow_session_lock_restore = true`.** Verified
  `false` and unset today. With it false, a QML crash while locked is an
  unrecoverable lockout — precisely the risk that has kept `Lock.qml`
  untested since Phase 7. Setting it makes a crashed lock screen
  restorable and turns that test from risky into routine. (06 §3)

**Found by sweeping the running session, not by reading the SPEC** — these
were missing from every doc until a coverage check on 2026-09-01:

- **`copyq` duplicates quickshell's own clipboard plugin.** Both run today;
  same pattern as mako and waybar, never noticed. (ROADMAP 13a)
- **Media/volume/brightness keys bypass the shell entirely**, so the OSD is
  driven second-hand — and the volume binds use a **hardcoded sink index**
  (`pactl set-sink-volume 0`), which can adjust the wrong device.
  (ROADMAP 13b)
- **Three wallpaper entry points** (`Super+W`, `Super+Shift+W` → nsxiv,
  and the Display panel button) plus the unwired picker. (ROADMAP Phase 8)
- **`scripts/watch-monitors.sh` exists only to work around awww's hotplug
  blindness** and is likely obsoleted by the QML crossfade. (Phase 8/11)
- **XDG portals were unpinned with five backends installed** — ✅ fixed:
  `configs/xdg/hyprland-portals.conf` pins `default=hyprland;kde`, GNOME's
  session stack removed.
- **Qt apps were completely unthemed** — `QT_QPA_PLATFORMTHEME=qt5ct` while
  qt5ct was **never installed**, so Qt silently fell back to its built-in
  default while GTK followed pywal. ✅ repointed at `kde`
  (plasma-integration), and `scripts/generate-kde-theme.sh` now regenerates
  `kdeglobals` from pywal on every wallpaper change — plus Plasma's own
  wallpaper.
- **Printing had no printer at all** — ✅ `nss-mdns` installed and wired into
  `/etc/nsswitch.conf` for `.local` discovery, `cups-pdf` installed **and its
  queue created** (the package does not create one), verified by a real test
  print. All reproducible from `install.sh`.
  All three are detailed in ROADMAP's "Beyond quickshell" section.

## Structural blockers

Two things gate several SPEC items and should be resolved before building
new panels — detail in 07 §4:

- **Panel anchoring.** Every hover panel anchors top-right, leaving the
  mid-bar clock trigger ~950px from its own panel. The SPEC puts *both*
  middle widgets behind hover panels. `mapToGlobal` and `mapToItem` have
  both already been tried and failed; do not retry blind.
- **Font-token split.** Gates the font picker (decision 2 above).

## Conventions these docs assume

- Theming is **wallust**-only, from `~/.cache/wal/colors.json` — wallust
  replaced pywal 2026-09-03 and writes the same paths, so nothing
  downstream changed (`pywal-wallust-migration.md`). There is still no
  multi-theme layer and one should not be added.
- Panels open on **hover**, not click. Deliberate, and confirmed by the
  SPEC saying "on hover" nine times. Any recommendation to revert is wrong
  for this repo.
- Persistent state changes go through `toggles/toggle-*.sh`. Native
  Quickshell bindings may *read* state; toggle scripts *write* it, so
  `menu.sh` and keybinds keep working when the shell is not running.
- Launch only via `restart.sh` — quickshell has no single-instance guard.
  Note it `exec`s in the foreground, so never wrap it in `timeout` (this
  took the bar down once during this session).
