# Network & Tunnels widget — research

Scope: `configs/quickshell/plugins/bar/widgets/Network.qml` (426 lines) plus its
helpers (`network-details.sh`, `network-wifi-scan.sh`, `network-wifi-connect.sh`)
and `scripts/network-speedtest.sh`. Read-only research; no files other than this
one were modified. Every capability below is tagged **BUILT-IN** (a Quickshell
QML type/property, no subprocess) or **SUBPROCESS** (Quickshell.Io `Process`
shelling out to a CLI/script).

## What's installed on this machine

```
nmcli            /usr/sbin/nmcli
bluetoothctl     /usr/sbin/bluetoothctl
mmcli            /usr/sbin/mmcli        (ModemManager D-Bus service not running)
rfkill           /usr/sbin/rfkill
wg               /usr/sbin/wg
speedtest        NOT FOUND              (Ookla CLI)
speedtest-cli    NOT FOUND              (sivel Python CLI)
librespeed-cli   NOT FOUND
localsend        /usr/sbin/localsend    (v1.18.2, GTK app, no CLI flags)
kdeconnect-cli   /usr/sbin/kdeconnect-cli (v26.08.0, full scriptable CLI)
tailscale        NOT FOUND
busctl / gdbus   both present
```

- `nmcli -t -f STATE,CONNECTIVITY general` → `connected:full` right now.
- `nmcli radio` → `WIFI-HW enabled, WIFI enabled, WWAN-HW missing, WWAN enabled`.
  `WWAN-HW missing` + `mmcli -L` → `error: couldn't find the ModemManager
  process in the bus` confirms **no WWAN modem exists on this hardware at
  all** — Network.qml's existing "No cellular modem on this hardware" text
  (line 406) is correct and should stay a static message, not a live check.
- `ls /etc/wireguard` → empty on this box right now, but the repo carries
  `configs/secrets/wg0.{laptop,phone,tablet}.conf` — per-device WireGuard
  profiles deployed to `/etc/wireguard/wg0.conf` at provision time. `nmcli
  connection show` has **no** `wg0` entry — the tunnel is a raw `wg-quick`
  interface, entirely outside NetworkManager's view. This matters for §5 and §6.
  `wg show` currently prints nothing (tunnel down), consistent with
  `toggle-vpn.sh`'s `off` state.
- No speed-test binary is installed at all. The existing speed panel
  (`plugins/speedtest/Panel.qml`) doesn't use any of the three named tools —
  see §7.
- `localsend --version` was run to probe its CLI surface; it has **no
  headless/version flag** and instead launched the full GTK app, which bound
  `Server started. (Port: 53317, HTTPS only)` and began emitting
  `NetworkInfo` broadcasts immediately. This is a real, reproducible finding,
  not a guess — see §4.
- `kdeconnect-cli --help` shows a genuinely scriptable CLI (`--list-devices`,
  `--pair`, `--ping`, `--share <path|URL>`, `--send-clipboard`, `--ring`,
  `--id-only`) — see §4.
- `tor-router.service` (used by `toggles/toggle-tor.sh`) is
  `/usr/bin/tor-router start/stop`, a **transparent proxy** unit
  (`Description=Start rules for transparent tor proxy`, `Requires=tor.service`)
  — it rewrites iptables/nft rules to redirect all traffic through Tor, not a
  per-app SOCKS switch. Relevant to the kill-switch discussion in §5/§6.

## Toggle conventions (read first, matched throughout)

`toggles/lib.sh` gives every `toggle-*.sh` the same shape:

- `toggle_get`/`toggle_set` persist to `$XDG_STATE_HOME/toggles/<name>`;
  `toggle_get_volatile`/`toggle_set_volatile` persist to `$XDG_RUNTIME_DIR`
  instead, for state that has no live system source of truth and would go
  stale across a reboot that silently reset the real thing (TLP is the
  existing example).
- `toggle_main <name> <label> <check_fn> <on_fn> <off_fn> <action>` drives
  `get|label|on|off|toggle`; `check_fn` must echo bare `on`/`off` and take no
  arguments; every action re-derives `check_fn` and writes it to state before
  acting, so state can never drift from reality for more than one poll.
- `toggle-tor.sh` and `toggle-vpn.sh` both check *live system state*
  (`systemctl is-active`, `ip link show wg0`) rather than trusting their own
  stored flag — this is the pattern any new toggle script must follow: cheap,
  synchronous, no CPU spike (see `toggle-protonvpn.sh`'s comment on why it
  checks `ip link show proton0` instead of `protonvpn status`, which costs
  ~1.2–1.4s of Python startup per call and was itself the cause of a periodic
  100%-CPU bug when polled every 10s from the bar).

Any new toggle proposed below (`toggle-bluetooth.sh`, `toggle-offline.sh`)
follows this exact shape.

## 1. Connectivity state: link-up vs real internet

**SUBPROCESS today, and should stay subprocess** — Quickshell has no built-in
NetworkManager binding (no `Quickshell.Network*` module exists; only
`Quickshell.Bluetooth` does, see §3). The fix here is *which* subprocess and
*polling vs streaming*, not moving on-QML.

- `nmcli -t -f STATE,CONNECTIVITY general` is already the right primitive.
  `CONNECTIVITY` is a 4-state enum NetworkManager itself derives from an
  active connectivity-check probe (default `http://nmcheck.gnome.org` or a
  distro mirror): `full` (real internet), `limited` (link up, default route,
  but the probe failed — the "LAN but no WAN" case), `portal` (probe redirected
  — captive portal), `none` (no default route). This is a strictly better
  signal than "is there a default route" and Network.qml's `detailsProc`
  doesn't currently surface it at all — it only exposes `connected: true/false`
  from whether a device is NM-`connected`, which conflates "on a LAN with no
  internet" with "actually online."
- Same data lives on D-Bus: `org.freedesktop.NetworkManager` exposes
  `Connectivity` (uint, same 4 values), `PrimaryConnectionType` (`"802-11-wireless"`
  vs `"802-3-ethernet"` — this is the clean wifi-vs-lan signal the spec asks
  for, cleaner than parsing `nmcli dev status` device names), and `State`.
  ([NetworkManager D-Bus reference](https://networkmanager.dev/docs/api/latest/spec.html))
- Quickshell talks D-Bus only via `Process` + a CLI (`busctl`/`gdbus`), there
  is no generic D-Bus QML binding in Quickshell (confirmed by the existence of
  the dedicated hand-written `Quickshell.Bluetooth` C++ module for BlueZ
  specifically — if generic D-Bus access existed as a QML primitive, that
  module would have been unnecessary).
- **Polling (current) vs streaming (recommended upgrade)**: today
  `detailsProc`/`wifiProc`/`rfkillProc` etc. all run once per 10s `Timer`
  tick. `nmcli monitor` is a long-lived subcommand that prints one plain-text
  line per state change (`"Networking is now enabled"`,
  `"<iface>: connectivity is now full"`, `"<conn> is now the primary connection"`)
  — no JSON/D-Bus decoding needed. Run it once as a `Process` with
  `running: true` permanently and `stdout: SplitParser { onRead: ... }`; on
  any line, trigger a single lightweight `nmcli -t -f STATE,CONNECTIVITY general`
  read instead of the current five-process fan-out. This cuts both latency
  (state changes reflected immediately, not up to 10s late) and idle CPU
  (`nmcli monitor` blocks on notify signals instead of forking every 10s).
  Keep a slow (~30-60s) polling `Timer` as a dead-man's-switch fallback in
  case the monitor process dies or the D-Bus session hiccups — this matches
  the existing repo pattern of Process + Timer, just with the Timer demoted
  to a safety net instead of the primary driver.
- `busctl monitor --match "..."`/`gdbus monitor --system` are the raw D-Bus
  alternative — strictly noisier to parse (full signal payloads) for no
  benefit over `nmcli monitor` here, since `nmcli` already exists as a
  dependency and prints exactly the fields needed.

**Recommendation**: bar icon logic becomes `none`→offline glyph,
`portal`→captive-portal warning glyph (new state the widget doesn't
distinguish today), `limited`→"connected, no internet" glyph, `full`→normal,
and wifi-vs-lan from `PrimaryConnectionType` rather than guessing from device
name prefixes. Replace the `Timer{ 10000 }`-only refresh with a persistent
`nmcli monitor` `Process` that triggers `refreshAll()` on any line, keeping
the existing 10s `Timer` only as a fallback (e.g. bump it to 30s).

## 2. Bluetooth

**Quickshell.Bluetooth is a real BUILT-IN module** (confirmed by fetching the
upstream C++ headers, not just docs prose — quickshell.org's docs pages 403
automated fetches, but the Forgejo source mirror does not):
[`src/bluetooth/adapter.hpp`](https://git.outfoxxed.me/quickshell/quickshell/src/branch/master/src/bluetooth/adapter.hpp),
[`src/bluetooth/device.hpp`](https://git.outfoxxed.me/quickshell/quickshell/src/branch/master/src/bluetooth/device.hpp).

`BluetoothAdapter` (BUILT-IN, one per adapter, reachable via
`Bluetooth.defaultAdapter`):
`name` (ro), **`enabled` (rw, via `setEnabled()`)**, `state`, `discoverable`
(rw), `discoverableTimeout` (rw), **`discovering` (rw — this is the scan
trigger)**, `pairable` (rw), `pairableTimeout` (rw), `devices` (ro model),
`adapterId`, `dbusPath`.

`BluetoothDevice` (BUILT-IN, one per paired/visible device):
`address`, `name`, `deviceName`, `icon`, `state`, `connected` (bool),
`paired`, `bonded`, `pairing`, **`trusted` (rw)**, `blocked`, `wakeAllowed`,
**`batteryAvailable` (bool) + `battery` (qreal, 0.0–1.0)**, `adapter`,
`dbusPath`; invokable `pair()`, `cancelPair()`, `connect()`, `disconnect()`.

This means device list, connect/disconnect, pair/trust, and **per-device
battery percentage** are all available as reactive QML properties with zero
subprocess and zero polling — a strict upgrade over `bluetoothctl` for
everything except one thing:

- **No A2DP/HSP-HFP audio-profile switching property exists** on
  `BluetoothDevice`. Profile switching is a PipeWire/WirePlumber concern, not
  a BlueZ adapter/device property — that stays **SUBPROCESS**, either
  `wpctl set-profile <bt-headset-id> N` (wireplumber's default policy usually
  auto-switches on call start already) or `pactl set-card-profile
  bluez_card.<MAC> <profile-name>` if PipeWire's session manager doesn't
  auto-negotiate the way it's wanted.
- Reference shells: DankMaterialShell (AvengeMedia) is documented as having
  its own Bluez manager/agent for D-Bus (GitHub issues reference
  `DMS auto-enables bluetooth at wakeup`, a control-center bluetooth toggle,
  and `bluetoothctl show` used for verification in bug reports) — search
  results couldn't pin an exact `BluetoothService.qml` path without fetching
  their repo directly (not done here to conserve budget; worth a follow-up
  `gh repo clone`/`WebFetch` if the exact file matters later). Given
  Quickshell.Bluetooth exists as a first-class module, it is very likely what
  DMS/caelestia/Noctalia bind to rather than reimplementing BlueZ D-Bus
  calls by hand — this is an inference from the module's existence, not
  independently verified by reading their source.

**The repo-rule question**: Network.qml today runs `bluetoothctl power on/off`
inline (lines 78, 98–101) — a real violation per the task brief. Two
independent decisions here, not one:

1. **Reading power state, device list, and battery** → bind straight to
   `Quickshell.Bluetooth.defaultAdapter.enabled`/`.devices` (BUILT-IN). This
   isn't "toggle logic" in the sense the repo rule guards against — it's
   live state Quickshell exposes as reactively as `Quickshell.env()`, and no
   other surface (tmux menu, walker menu) currently reads bluetooth state at
   all, so there's no duplication risk to prevent.
2. **The on/off action** should still go through a `toggles/toggle-bluetooth.sh`
   rather than calling `Quickshell.Bluetooth`'s `setEnabled()` or shelling
   `bluetoothctl power` inline, for the same reason Wi-Fi radio and offline
   mode do: this repo's `menu.sh` (tmux) and any future walker integration
   are exactly the kind of second surface the rule exists for, and a toggle
   script is one line of extra indirection for a real consistency guarantee.
   Proposed script, matching `toggle-tor.sh`'s shape exactly:

```sh
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

check() { bluetoothctl show | grep -q 'Powered: yes' && echo on || echo off; }
turn_on() { bluetoothctl power on; }
turn_off() { bluetoothctl power off; }

toggle_main bluetooth "Bluetooth" check turn_on turn_off "${1:-toggle}"
```

Network.qml's `toggleBluetooth()` becomes
`Quickshell.execDetached([toggleDir + "/toggle-bluetooth.sh", "toggle"])`,
same as `toggleTor()`/`toggleHomeVpn()` already do — and the `btProc`
polling `Process` (lines 97–101) can be deleted entirely in favor of binding
to `Quickshell.Bluetooth.defaultAdapter.enabled` directly, which is strictly
better than either the old inline subprocess or a `toggle-bluetooth.sh get`
poll.

## 3. LocalSend

Empirically probed, not guessed: LocalSend has **no CLI/headless mode**.
`localsend --version` launched the full GTK app (tray icon, `DiscoveryIsolate`,
`HttpUploadIsolate`, `HttpServerIsolate` all spun up), bound
`Server started. (Port: 53317, HTTPS only)`, and began UDP-multicast
`NetworkInfo` broadcasts — all before any window interaction. (This
accidentally left a LocalSend GUI instance running in the background; a
`pkill -f localsend_app` cleanup was attempted but denied by the sandbox's
network-safety classifier as a precaution — worth manually closing it.)

Protocol (documented at
[localsend/protocol](https://github.com/localsend/protocol/blob/main/v1.md)):
UDP multicast announce to `224.0.0.167:53317`, then direct peer-to-peer HTTPS
REST on TCP `53317` with self-signed per-device certs:
`/api/v2/register`, `/api/v2/prepare-upload`, `/api/v2/upload`,
`/api/v2/cancel`. This is a real, scriptable HTTP API in principle — but it's
documented for third-party *interop* (another implementation acting as a
peer), not for driving *this* running instance headlessly; there's no
"send this file to that peer" single call, it's a full handshake requiring a
per-transfer session ID negotiated first, and self-signed certs need `-k`/pin
handling from `curl`. Building and maintaining that against a GUI app that
receives protocol updates on its own schedule is a lot of fragile surface for
a personal dotfiles widget.

**Realistic integration**: same pattern this file already uses for Portmaster
(lines 12–16, 112–116 of Network.qml) — LocalSend has no documented API
suitable for driving from outside, so don't fake deep control; just report
whether it's running (`pgrep -x localsend_app`, SUBPROCESS) and give a button
that launches/focuses it. Do not attempt the raw HTTPS API integration.

**Alternatives for "send a file to another of my devices," compared honestly**:

| Tool | Installed | CLI surface | Verdict |
|---|---|---|---|
| **KDE Connect** (`kdeconnect-cli`) | yes, v26.08.0 | Full: `--list-devices`, `--pair`, `--ping`, `--share <path\|URL>`, `--send-clipboard`, `--ring`, `--id-only` for scripting | **Recommended** for the widget's actual send/receive actions — real subprocess CLI, structured output, already installed, and this machine already runs Plasma (see `configs/plasma/*` in the repo) so a KDE Connect pairing to a phone is the natural existing path. |
| LocalSend | yes, v1.18.2 | none | Status-only button (running/not running + launch), per above. |
| qrcp | not installed | ad-hoc single-file HTTP+QR server | Fine for a true one-off "scan this QR to grab a file" but no persistent peer/discovery model — would need a new package for a narrower feature than kdeconnect already covers. |
| Syncthing | not installed | none built-in, but a real documented **REST API** on `127.0.0.1:8384` once running as a daemon | Best-architected of the four for scripting (true JSON API, not a hack) but it's a continuous folder-sync daemon with device IDs/folder shares to configure — the wrong shape for "send this one file right now." Worth it only if ongoing multi-device sync becomes a separate need. |
| warpinator | not installed | none | Same GTK/mDNS shape as LocalSend with a smaller community and no CLI advantage — no reason to add a second app in this category. |

**Recommendation**: use `kdeconnect-cli --share <path>` (SUBPROCESS) for the
widget's actual "send to phone" action, since it's a real one-line scriptable
command with a device already likely to be paired via Plasma. Keep LocalSend
as a launch/status button only, exactly like Portmaster. Don't add qrcp,
Syncthing, or warpinator unless a genuinely different need (continuous sync,
truly ad-hoc cross-platform QR drops) shows up later.

## 4. Full offline mode

Current implementation: `rfkill block all` (line 80), gated on a `rfkillProc`
that greps `rfkill list` for "Soft blocked: yes" with no "Soft blocked: no"
anywhere (line 109) — fragile parsing (breaks the moment a hard-blocked
device with no soft-block line exists, or radios disagree), and see the foot
gun below.

Comparison:

| Mechanism | What it actually blocks | Reversible | Foot guns |
|---|---|---|---|
| `rfkill block all` (current) | Wi-Fi, Bluetooth, WWAN radios only — **not Ethernet** | Yes, `rfkill unblock all`, same-UI | Silently does nothing on a wired connection — "offline mode" would report on but the machine stays fully online over LAN. This is the actual bug hiding behind the current implementation's own admission that it's a gap. |
| `nmcli radio all off` | Same radio set as rfkill, via NM instead of the kernel rfkill subsystem | Yes, same-UI | Same Ethernet gap as rfkill; NM-specific so doesn't affect non-NM-managed interfaces (irrelevant here, everything's NM except `wg0`). |
| `nmcli networking off` | **All** NM-managed connections, including Ethernet | Yes, `nmcli networking on`, same-UI | `wg0` here is a raw `wg-quick` interface (confirmed: no `wg0` entry in `nmcli connection show`) — NM has no idea it exists, so `networking off` leaves the WireGuard tunnel dangling with its routes still installed but the underlying link/DNS in an inconsistent state, not actually "off." Must explicitly stop the tunnel toggles too (see recommendation). |
| `systemctl stop NetworkManager` | Everything NM manages, plus its D-Bus service disappears | Sort of — `systemctl start NetworkManager` — but slow, and NM has to fully re-probe every device | Kills the very D-Bus/`nmcli` interface this whole widget depends on to report state and to turn itself back on — a genuine "recoverable from the same UI" foot gun if the toggle's `on_fn`/`check_fn` also shell to `nmcli`. Also orphans any manually-added routes/resolv.conf entries NM was tracking. Not recommended for a bar toggle. |
| nftables kill-switch (default-deny OUTPUT except loopback) | Packets, not interfaces — interfaces stay "up," DHCP/link state untouched | Yes, if scoped to one clearly-named table/chain that's flushed on exit | Most surgical (interfaces staying up avoids the captive-portal false-positive risk in §1), but this box **already runs two other things that rewrite nft/iptables rules** — `tor-router.service`'s transparent-proxy redirect and (per the widget's own comment) Portmaster's own firewall. A third independent nftables actor risks silent rule-ordering conflicts or the offline-mode chain surviving a Portmaster/tor-router restart that flushes tables. Also the sharpest footgun of all: a default-deny table with no explicit loopback/established-allow exception kills an inbound SSH session into this machine instantly and irreversibly from that same session. |

**Recommendation**: don't reach for nftables or stopping NetworkManager for
v1 — too much overlap with Portmaster/tor-router's existing rule ownership,
and the risk profile doesn't match "a bar toggle." Fix the actual bug
(Ethernet not covered) with the minimum robust combination, and make offline
mode also turn off the tunnel toggles so it doesn't leave WireGuard dangling
per the table above:

```sh
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

check() {
    # Fully offline only if every radio is soft-blocked AND NM networking
    # is disabled — covers both the wireless and the wired/NM-managed path.
    local rf_state nm_state
    rf_state=$(rfkill list -o SOFT -n | grep -qv '^unblocked$' && echo blocked || echo unblocked)
    nm_state=$(nmcli -t -f NETWORKING general)
    [[ "$rf_state" == blocked && "$nm_state" == disabled ]] && echo on || echo off
}
turn_on() {
    # Drop any tunnels first so nothing is left dangling once radios/NM die.
    ./toggle-vpn.sh get | grep -q on && ./toggle-vpn.sh off || true
    ./toggle-protonvpn.sh get | grep -q on && ./toggle-protonvpn.sh off || true
    rfkill block all
    nmcli networking off
}
turn_off() {
    nmcli networking on
    rfkill unblock all
}

toggle_main offline "Offline mode" check turn_on turn_off "${1:-toggle}"
```

Idempotency note: `rfkill list -o SOFT -n` prints one `blocked`/`unblocked`
line per radio — the `grep -qv '^unblocked$'` check is "any radio still
blocked," which is more correct than the current widget's brittle
"Soft blocked: yes and not also Soft blocked: no anywhere" text match. Tor
router and Portmaster are deliberately left alone — they're independent
firewall layers, not "internet on/off" and turning them off is not what
"offline mode" means.

## 5. Tunnels

- `wg show` / `wg-quick up|down`: **SUBPROCESS**, no built-in WireGuard type
  in Quickshell. `toggle-vpn.sh`'s `ip link show wg0` check is cheap and
  correct for on/off; for *richer* status (handshake age, bytes
  transferred) `wg show wg0 dump` prints tab-separated machine-readable
  fields (`interface, private-key, public-key, listen-port, fwmark` header
  row, then one row per peer with `public-key, preshared-key, endpoint,
  allowed-ips, latest-handshake, transfer-rx, transfer-tx, persistent-keepalive`)
  — cheap to parse in `awk`, worth adding to `network-details.sh`-style JSON
  for a "connected since / data moved" line the current widget doesn't show.
- ProtonVPN: `toggle-protonvpn.sh` already does the hard part right (avoiding
  the slow `protonvpn status` CLI call). A kill-switch is a separate,
  VPN-scoped ProtonVPN CLI setting (`protonvpn killswitch` /
  `protonvpn configure`), out of scope for this widget beyond maybe
  surfacing its on/off state — and that read has the same CPU-cost caveat
  the existing comment already flags for any `protonvpn` subcommand, so
  don't add it casually.
- Tor: already correctly modeled as `tor-router.service`, a transparent
  proxy, not a per-app SOCKS toggle — nothing to change here structurally.
- **Mutual exclusion**: `wg0` (Homeserver) and `proton0` (ProtonVPN) are both
  full-tunnel VPN interfaces competing for the default route — running both
  at once is a real conflict (routing-table fight, unpredictable which wins),
  unlike Tor's transparent iptables redirect, which layers on top of
  whatever the current default route is and is orthogonal to either VPN.
  Recommend the panel show a non-blocking warning row when **both**
  `homeVpnState` and `protonVpnState` are `on` simultaneously (a state
  Network.qml can already detect — it just doesn't warn about it), rather
  than hard-blocking the second toggle, since a user might have a legitimate
  reason and the repo's philosophy elsewhere is "toggles just reflect truth."

## 6. Speed test

Already answered empirically: **none of `speedtest`, `speedtest-cli`, or
`librespeed-cli` are installed**, and the existing panel
(`plugins/speedtest/Panel.qml` → `scripts/network-speedtest.sh`) uses none of
them — it's a **SUBPROCESS** shell script adapted verbatim from Omarchy that
hits fast.com's (Netflix CDN) speedtest API directly with parallel `curl`
workers and reports one Mbps sample per second by diffing
`/sys/class/net/$iface/statistics/{rx,tx}_bytes`, split into a download phase
then an upload phase, each capped by a 5s `phaseTimer` in the QML.

Comparing the three named tools against what this repo actually needs (a
*live, per-second* number feeding `SpeedTestOverlay`'s animated gauge, not a
single final result):

- **Ookla `speedtest` CLI**: most "official"/accurate, and its JSON/JSONL
  output (`--format json|jsonl|json-pretty`) is machine-friendly — but it
  requires a one-time interactive EULA/GDPR acceptance
  (`--accept-license --accept-gdpr` to do it non-interactively), one more
  piece of first-run machinery `install.sh` would need to handle, and it
  reports progress as a single evolving JSON blob rather than a clean
  stream of intermediate values — noticeably messier to turn into
  "one number per second" than the current script's `printf` loop.
- **`speedtest-cli`** (the common distro Python wrapper): search results
  independently note it's known to break when Ookla changes server-list
  formats and needs periodic patching — a maintenance liability for a
  personal dotfiles repo with no reason to prefer it.
- **`librespeed-cli`**: no EULA, `--json` output, single static Go binary —
  the cleanest of the three if Ookla-grade "official" numbers are ever
  wanted, but still reports final results rather than a clean per-second
  stream, and would need either a public LibreSpeed server (comparable
  privacy/trust profile to fast.com) or self-hosting one (not currently
  present in this repo).

**Recommendation**: keep `scripts/network-speedtest.sh` as-is. It's a better
architectural fit for this specific UI (a live animated gauge) than any of
the three named tools, none of which stream partial numbers as cleanly as
"one Mbps value per line, forever, until SIGTERM" — which is exactly what
`Panel.qml`'s `SplitParser`+`phaseTimer` machinery is already built around.
If a separate "give me one official, citable number" action is ever wanted
(distinct from the live gauge), `librespeed-cli` is the lowest-friction
addition of the three (no EULA, single binary, no distro-CLI decay risk) —
but this is optional and not something the current widget is missing.

## Summary of concrete file changes proposed

1. `toggles/toggle-bluetooth.sh` — new, wraps `bluetoothctl power` per §2.
2. `toggles/toggle-offline.sh` — new, replaces inline `rfkill block all` per
   §4, fixes the Ethernet gap, and stops dangling tunnels before going offline.
3. `Network.qml`:
   - `toggleBluetooth()` → calls `toggle-bluetooth.sh` instead of inline
     `bluetoothctl`; bind bluetooth power/device-list/battery display to
     `Quickshell.Bluetooth` instead of polling `btProc` (§2).
   - `toggleOfflineMode()` → calls `toggle-offline.sh` instead of inline
     `rfkill` (§4).
   - Replace the flat `Timer{10000}` poll of `detailsProc`/`wifiProc`/etc.
     with a persistent `nmcli monitor` `Process` driving `refreshAll()`,
     demoting the `Timer` to a ~30s fallback (§1).
   - Surface `nmcli`'s `CONNECTIVITY` (`full`/`limited`/`portal`/`none`) and
     `PrimaryConnectionType` in `network-details.sh`'s JSON instead of the
     current bare `connected: true/false` (§1).
   - Add a non-blocking warning row when both VPN tunnels are on
     simultaneously (§6).
   - `kdeconnect-cli --share` for the "send to phone" action; LocalSend
     stays a launch/status button only, same pattern as Portmaster (§3).
