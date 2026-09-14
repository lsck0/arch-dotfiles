# Third-party notices

This directory's QML is heavily derived from
[basecamp/omarchy](https://github.com/basecamp/omarchy)'s `shell/` (Quickshell
desktop shell). Per the "full 1:1 port" decision recorded in this repo's
`TODO.md` (2026-08-30, since folded into `research/ROADMAP.md`), most of
upstream's plugin surface has since been
ported here too, adapted where this repo's architecture differs: no
`OMARCHY_PATH`/distro-checkout layer, no `shell.toml` theme-override layer
(one pywal-fed theme, not swappable themes), hover-driven panel-open instead
of click-to-toggle, and this repo's own toggle scripts / state directories in
place of Omarchy's `bin/` CLI and `~/.local/state/omarchy/`. Files are copied
verbatim, copied with light renaming, or substantially adapted — each file
that derives from upstream says which, in its own header comment; this list
is a provenance index, not a substitute for reading those.

Not listed here: anything with no upstream equivalent (`System.qml`,
`Weather.qml`, `Costs.qml`, `Agents.qml`, the toggles system, herdr config,
and everything else original to this repo) — several of those files mention
omarchy in a comment only to explain why they're *not* a port of the
upstream plugin with the same name.

## Shared infrastructure

- `Commons/Color.qml`, `Commons/Style.qml`, `Commons/Util.qml`,
  `Commons/Border.qml` — trimmed derivatives (theme-override layer removed,
  per-surface override resolution removed since there's one look, not
  swappable themes)
- `Ui/BarWidget.qml`, `Ui/WidgetButton.qml`, `Ui/BarIconButton.qml`,
  `Ui/BarIndicator.qml`, `Ui/OpticalGlyph.qml`, `Ui/Button.qml`,
  `Ui/KeyboardPanel.qml`, `Ui/PointerMoveGate.qml` — near-verbatim
- `services/AppLibrary.qml` — adapted (OMARCHY_PATH → `Quickshell.shellDir`,
  OSD/launch-feedback CLI → this repo's own IPC-based OSD contract, no
  `omarchy-remove-launcher-entry` equivalent so `remove()` is a no-op)
- `shell.qml` — the plugin-registry/dynamic-loader machinery
  (`PluginRegistry`/`BarWidgetRegistry`/service and panel loaders) is a
  structural port of upstream's own plugin host, adapted for this repo's
  single-bar, no-distro-checkout setup

## Bar (`plugins/bar/`)

`Bar.qml` itself is adapted (hover-open instead of click-toggle — a
deliberate, explicitly-requested deviation from 1:1, see
`research/ROADMAP.md`).
Verbatim-or-near-verbatim widgets: `Workspaces.qml`, `ActiveWindow.qml`,
`Microphone.qml`, `AudioIO.qml`, `Clock.qml`, `Weather.qml` (partial —
Omarchy-specific bits swapped), `Media.qml`, `Toggles.qml`, `Network.qml`,
`Display.qml`, `Tray.qml`, `KeyboardLayout.qml`, `Spacer.qml`. Adapted (CLI
or backend swapped for a local equivalent, UI mostly kept):
`SystemUpdate.qml` (`omarchy-update-available` → `checkupdates`),
`Indicators.qml` (simplified to the 3 indicators this repo has real backing
for — Dnd/StayAwake/Reminder — instead of upstream's dynamic 6-indicator
registry), `Notifications.qml` (bridges this repo's own notification daemon
instead of mako). Indicators (`plugins/bar/indicators/`): `Dnd.qml`,
`StayAwake.qml`, `Reminder.qml` — adapted to poll this repo's own toggle/
reminder scripts on a Timer instead of upstream's `indicatorHost`
push-refresh signal (not wired in this repo's simplified `Indicators.qml`).
Not ports: `AppMenu.qml` (originally launched `walker`; now toggles this
repo's own `plugins/appsearch/`, upstream's equivalent is a completely
different, much larger command-menu plugin — see that file's own header),
`Battery.qml`/`BatteryModel.js` (rebuilt against `Quickshell.Services.UPower`
+ this repo's TLP-based power toggle instead of upstream's CLI-shelling +
power-profiles-daemon approach).

## Net-new plugins (Phase 5/6/7)

Each of these has a fuller adaptation writeup in `research/ROADMAP.md`'s
Appendix B and each file's own header, covering the old Phase 5-7
entries; summarized here for provenance:

- `plugins/notifications/` (`Service.qml`, `NotificationLogic.js`,
  `components/NotificationCard.qml`) — the active notification daemon,
  replacing mako. `NotificationLogic.js` is verbatim (pure functions).
  `Service.qml` adapted: state dir, dropped the `shell.bar`-dependent
  position/clearance logic (this repo has one fixed top bar), `focusApp()`
  rewritten from an OMARCHY_PATH bin/ script to inline `hyprctl`.
- `plugins/appsearch/` (`AppSearch.qml`) — **not a port**: a purpose-built
  app launcher replacing `walker`, backed by the already-ported
  `AppLibrary.qml`/`AppSearch.js`, not upstream's much larger generic
  command-menu engine (`plugins/menu/` upstream, ~2051 lines) — see the
  file's own header for why porting that wholesale was out of scope.
- `plugins/clipboard/` (`Clipboard.qml`, `ClipboardHistory.js`,
  `capture.sh`) — upgraded to upstream's fuller picker (preview pane, image
  thumbnails, `PointerMoveGate`, confirm-dialog clear). Backend stays
  wl-copy/xdg-open (no `omarchy-clipboard-paste-*` binaries here).
  `ClipboardHistory.js`/`capture.sh` are verbatim.
- `plugins/speedtest/`, `plugins/disk-speedtest/` (`Panel.qml`) — adapted
  (upstream CLI names → `scripts/network-speedtest.sh`/
  `scripts/disk-speedtest.sh`, this repo's own verbatim ports of
  `omarchy-network-speedtest`/`omarchy-disk-speedtest`). Reuse the
  unmodified `Ui/SpeedTestOverlay.qml`.
- `plugins/wifiqr/` (`Panel.qml`, `Model.js`) — adapted (script names →
  `scripts/network-qr.sh`/`scripts/network-password.sh`, this repo's own
  verbatim ports of `omarchy-network-qr`/`omarchy-network-password`).
  `Model.js` is verbatim.
- `plugins/emojis/` (`Emojis.qml`, `EmojiSearch.js`, `emojis.json`) —
  `EmojiSearch.js` and `emojis.json` (1870 entries) verbatim; `Emojis.qml`
  adapted (`Border.surfaceSpec` → `Border.flat`, no `wtype` auto-paste —
  copy-only, matching `Clipboard.qml`'s own precedent).
- `plugins/image-picker/` (`ImagePicker.qml`, `ImagePickerModel.js`,
  `list.sh`) — `ImagePickerModel.js` verbatim; `ImagePicker.qml` adapted
  (default image directory → this repo's `wallpapers/`); `list.sh` verbatim
  except its cache directory. Standalone, general-purpose — not wired to
  replace `scripts/switch-wallpaper.sh`'s existing interactive picker.
- `plugins/reminders/` (`ReminderFlow.qml`, `ReminderFlowModel.js`) —
  `ReminderFlowModel.js` verbatim; `ReminderFlow.qml` adapted (script names
  → `scripts/reminder.sh`/`scripts/notification-send.sh`, this repo's own
  ports of `omarchy-reminder`/`omarchy-notification-send`).
- `plugins/background/Background.qml`, `plugins/osd/Osd.qml`,
  `plugins/osd/OsdModel.js` — adapted (Omarchy-specific theme/CLI
  integrations replaced with this repo's pywal/wallpaper-script
  equivalents).

## External data sources and runtime dependencies

Not derived code — these are services the shell queries at runtime, and
packages it needs present. Listed here because their terms are what make
the querying allowed, and because "where does this number come from" is a
question this file should answer.

| Source | Used by | Terms as they affect us |
| --- | --- | --- |
| [Open-Meteo](https://open-meteo.com/) | `weather-fetch.sh`, `weather-field.sh` | Free for non-commercial use, no API key. CC-BY-4.0 data; attribution is shown in the weather panel's provenance line. `weather-field.sh` sends a 25-point grid in one request, well inside the free tier's call budget. |
| [RainViewer](https://www.rainviewer.com/api.html) | `weather-radar.sh` | Free public API, no key. **Attribution is a licence condition** — the panel renders "radar © RainViewer" whenever frames are shown, and `manifest.json` carries the string so the widget cannot display the loop without it. |
| [MeteoAlarm](https://meteoalarm.org/) (EUMETNET) | `weather-alerts.sh` | Free, unauthenticated CAP feeds from ~38 European national met services. Warnings are re-presented as structured fields only (event, awareness level, relative times) — no headline, description or instruction text is emitted, which also keeps us clear of redistributing their prose. |
| [Nominatim](https://nominatim.org/) / OpenStreetMap | `weather-alerts.sh` | Reverse geocoding, to decide which CAP region applies. ODbL data. Their usage policy requires an identifying `User-Agent` (sent) and forbids heavy automated use — the answer is cached for 30 days, since administrative boundaries do not move. The result is used only for region matching and is never displayed, so no on-screen OSM attribution is due. |
| `python-websocket-client` | `obs-status.py` | Apache-2.0. Packaged on Arch as `python-websocket-client`; pulled in by `install.sh`. |
| [obs-websocket](https://github.com/obsproject/obs-websocket) (protocol) | `obs-status.py` | GPL-2.0-or-later, and shipped inside OBS Studio — we implement its v5 client handshake against the user's own local server, linking nothing. |
| [BetterDiscord](https://betterdiscord.app/) (plugin API) | `configs/discord/plugins/QuickshellVoiceStatus.plugin.js` | First-party plugin written for this repo, not a port. It targets BetterDiscord's `BdApi` surface; BetterDiscord itself is Apache-2.0 and is installed separately by the user. |

## Scripts (`scripts/`)

Verbatim ports of Omarchy `bin/` scripts, renamed and symlinked via this
repo's own `scripts/link.sh` convention instead of an `OMARCHY_PATH` bin
directory:

- `network-speedtest.sh` ← `omarchy-network-speedtest`
- `disk-speedtest.sh` ← `omarchy-disk-speedtest`
- `network-qr.sh` ← `omarchy-network-qr`
- `network-password.sh` ← `omarchy-network-password`
- `notification-send.sh` ← `omarchy-notification-send`
- `reminder.sh` ← `omarchy-reminder` (adapted: state dir/unit prefix,
  dropped an indicator-refresh IPC call this repo has no equivalent for)

Per omarchy's MIT license, its copyright and permission notice:

> Copyright (c) David Heinemeier Hansson
>
> Permission is hereby granted, free of charge, to any person obtaining
> a copy of this software and associated documentation files (the
> "Software"), to deal in the Software without restriction, including
> without limitation the rights to use, copy, modify, merge, publish,
> distribute, sublicense, and/or sell copies of the Software, and to
> permit persons to whom the Software is furnished to do so, subject to
> the following conditions:
>
> The above copyright notice and this permission notice shall be
> included in all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
> EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
> MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
> NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
> LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
> OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
> WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
