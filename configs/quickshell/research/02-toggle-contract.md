# Toggle contract: which SPEC settings must go through `toggles/`

Written from a local audit of the repo, not from web research. This doc
exists because the SPEC says:

> Make sure settings that require changes in dotfiles are properly done and
> not just hacked together, use the "toggle" system for those.

This is the design authority for that requirement. Anything under
`configs/quickshell/` that mutates persistent state must conform to it.

---

## 1. The rule, stated precisely

From `skills/l-dotfiles`:

> `toggles/*.sh` is the only place toggle logic should live — UIs
> (waybar/quickshell/herdr) should shell out to these, never reimplement
> the logic.

Restated as a contract with three obligations:

1. **QML never mutates persistent state directly.** No `sed -i`, no writing
   into `~/.config/*`, no `hyprctl keyword` for something meant to persist,
   no `rfkill`/`bluetoothctl`/`systemctl` state changes inline.
2. **QML reads state by asking the same script.** Every toggle exposes
   `get`; the widget polls or invokes that, and never infers state from a
   local QML property it set itself.
3. **The script is the only thing that knows the mechanism.** If the
   backend changes (TLP → power-profiles-daemon, `rfkill` → `nmcli`), only
   the script changes; no QML edit is required.

The payoff is not purity. It is that `toggles/menu.sh`, the waybar status
script, herdr, a keybind, and the quickshell widget all get the same
behaviour for free, and that state survives a shell restart.

## 2. The existing idioms (cite these, don't invent new ones)

### 2a. Binary on/off — `toggle_main`

`toggles/lib.sh` provides:

```bash
# toggle_main <name> <label> <check_fn> <on_fn> <off_fn> <action>
# check_fn must echo "on" or "off" and take no arguments.
toggle_main dnd "Do Not Disturb" check turn_on turn_off "${1:-toggle}"
```

Actions: `get | label | on | off | toggle`. `toggle-dnd.sh` is the
reference implementation and is *already* the model for how quickshell
should integrate — note that its `check`/`on`/`off` shell back into
quickshell over IPC:

```bash
qs_ipc() { quickshell ipc -p "$HOME/.config/quickshell" call notifications "$@"; }
check() { qs_ipc isDnd; }
```

So the dependency direction is not one-way. A toggle may drive quickshell
via IPC, and a quickshell widget may drive a toggle via `Process`. What is
forbidden is the widget skipping the script and doing the work itself.

### 2b. Multi-state enum — the `toggle-powermode.sh` shape

`toggle_main` is binary only. For an enum, `toggle-powermode.sh` hand-rolls
a `case` with `STATES`/`ICONS`/`LABELS` arrays and supports
`get | label | toggle | <explicit-state>`. `toggle` cycles; passing a state
name sets it directly. **This is the pattern to copy for anything with a
small fixed set of values**, and the SPEC's powermode row maps onto it
one-to-one (powersave / balanced / performance — note the script spells it
`power-saver`).

### 2c. State that a reboot silently clears — the volatile store

Also from `toggle-powermode.sh`, and a subtlety worth preserving:

> TLP has no clean query for "currently forced state", so we track it
> ourselves in tmpfs, not the persistent store: tlp.service always resets to
> auto-detect on boot, so a persistent flag would lie about the state a
> reboot already cleared.

`toggle_get_volatile`/`toggle_set_volatile` (backed by `XDG_RUNTIME_DIR`)
exist for exactly this. Rule of thumb: **if `check_fn` can query the real
system, do that; if it cannot and the underlying state dies at reboot, use
the volatile store; use the persistent store only when the setting itself
is persistent.**

## 3. The gap: there is no idiom for a value-carrying setting

The SPEC needs settings that are neither boolean nor a 3-item enum:

- font family — **4174 families installed** (`fc-list : family | ...`)
- font size — small integer, effectively unbounded
- monitor scale — per-monitor float
- wallpaper — a path from a directory of images

`toggle_main` cannot express these, and copying the `powermode` `case`
block for a 4174-element list is absurd. This is a real architectural gap
and should be closed deliberately rather than by each widget improvising
(which is exactly how the current violations happened).

**Proposed extension — a "setting" flavour of the same CLI**, so callers
stay uniform:

| action | meaning |
| --- | --- |
| `get` | print the current value |
| `label` | human-readable line for `menu.sh` |
| `list` | print all valid values, one per line (for a picker UI) |
| `set <value>` | apply and persist, idempotently |

`toggle-powermode.sh` already implements `get`/`label`/`set`-by-name; this
adds only `list` and generalises the value space. Keeping the file naming
(`toggles/toggle-font.sh`) avoids a second directory and keeps
`install.sh`/`menu.sh` discovery unchanged — though `menu.sh` will need to
learn to skip or submenu the ones whose `list` is huge.

Open question for the owner: `toggles/` currently means "things you flip".
A 4174-item font picker stretches that word. The alternative is a sibling
`settings/` directory with the same CLI shape. **Recommendation: keep it in
`toggles/`** — one discovery mechanism, one convention, and the `list`
action makes the distinction explicit without a second concept.

## 4. The contract table

Every SPEC feature, whether it mutates persistent state, and who owns it.

| SPEC feature | Mutates persistent state? | Owner | Status |
| --- | --- | --- | --- |
| Powermode (powersave/balanced/performance) | yes (until reboot) | `toggle-powermode.sh` | ✅ correct, reference impl |
| DND / disable all notifications | yes | `toggle-dnd.sh` | ✅ correct, IPC-backed |
| Tor | yes | `toggle-tor.sh` | ✅ correct |
| VPN / ProtonVPN | yes | `toggle-vpn.sh`, `toggle-protonvpn.sh` | ✅ correct |
| WireGuard homeserver | yes | `toggle-vpn.sh` | ✅ correct |
| Keep awake / idle inhibit | yes | `toggle-keep-awake.sh` | ✅ correct |
| **Offline mode** | yes | **`toggle-offline.sh` (MISSING)** | ❌ `Network.qml` runs `rfkill block all` inline |
| **Bluetooth power** | yes | **`toggle-bluetooth.sh` (MISSING)** | ❌ `Network.qml` runs `bluetoothctl power` inline |
| **Font family** | yes — many dotfiles | **`toggle-font.sh` (MISSING)** | ❌ `Display.qml` runs `sed -i` from QML |
| **Font size** | yes — many dotfiles | **`toggle-font.sh` (MISSING)** | ❌ same |
| **Monitor scale** | yes — `hyprland_monitors.lua` | **`toggle-monitor-scale.sh` (MISSING)** | ❌ `Display.qml` uses runtime-only `hyprctl keyword` |
| **Wallpaper** | yes — pywal cache + all themed apps | `scripts/switch-wallpaper.sh` | ⚠️ works, but is a script not a toggle; needs a `get`/`list`/`set` CLI so a native picker can drive it |
| Screen brightness | no — volatile, `brightnessctl` | widget may call directly | ✅ fine as-is |
| Audio volume / mute / device | no — PipeWire runtime | widget may call directly | ✅ fine as-is |
| Wifi network selection | NetworkManager owns persistence | `nmcli` via helper scripts | ✅ acceptable — NM is the store |
| Media transport (play/pause/next) | no | MPRIS direct | ✅ fine |
| Pomodoro / reminders | app-local state | quickshell-owned | ✅ fine, not a dotfile |

**Rule of thumb for the "may call directly" rows:** if the setting dies
when the process/session dies and no file records it, the widget may drive
it directly. If it outlives the session, it belongs to a toggle.

## 5. The four violations, in detail

### 5a. `Display.qml` — font family and size via `sed -i` from QML

`configs/quickshell/plugins/bar/widgets/Display.qml`:

```qml
function setFont(family) {
  Quickshell.execDetached(["bash", "-lc",
    "sed -i \"s/font-family = .*/font-family = " + family + "/\" ~/.config/ghostty/config; " +
    "sed -i 's/\"buffer_font_family\": \"[^\"]*\"/\"buffer_font_family\": \"" + family + "\"/;" +
    "s/\"ui_font_family\": \"[^\"]*\"/\"ui_font_family\": \"" + family + "\"/' ~/.config/zed/settings.json"])
}
```

Five separate problems:

1. **Architecture** — QML is editing dotfiles. Forbidden by the repo rule.
2. **Coverage of the file** — the zed regex hits `buffer_font_family` and
   `ui_font_family` but **misses the third pair** at
   `configs/zed/settings.json:44-45` (`font_family` / `font_size` inside
   the terminal block). Changing the font leaves the terminal on the old
   one. This is a live bug, not a style complaint.
3. **Coverage of the system** — the font is *also* pinned in
   `configs/emacs/early-init.el:13`, `configs/discord/wal.theme.css:23`,
   nvim's `guifont`, waybar's CSS, and quickshell's own
   `Commons/Style.qml:143`. None are touched, so "set the font" sets it in
   one and a half apps out of seven.
4. **Choice set** — `fontChoices` is hardcoded to four families; the SPEC
   says "any installed font". There are 4174.
5. **No readback** — nothing implements `get`, so the panel cannot show
   which font is actually active; it compares against `Style.fontFamily`,
   which the function never updates.

Not a problem, contrary to first suspicion: `~/.config/ghostty` is a
symlinked *directory* (`configs/link.sh` does `ln -sf ${PWD}/ghostty
${HOME}/.config/ghostty`), so `sed -i` on a file *inside* it rewrites the
repo file and does not break the symlink. Persistence works. The
architecture is what is wrong. (Verified: `sed -i` on a symlinked *file*
would replace it with a regular file — that would have been a real
corruption bug, and it is worth never introducing.)

**Fix:** `toggles/toggle-font.sh` with `get | label | list | set <family>`
and a companion `set-size <n>`, owning every call site above, plus a
quickshell IPC call so the running bar restyles without a restart. See §6
for the icon-font caveat, which blocks part of this.

### 5b. `Network.qml` — offline mode inline

```qml
function toggleOfflineMode() {
  Quickshell.execDetached(["rfkill", offlineModeOn ? "unblock" : "block", "all"])
  Qt.callLater(refreshAll)
}
```

The file's own header comment concedes the point:

> Bluetooth/wifi/offline mode are new here since `toggles/` doesn't cover
> them.

That was a reasonable note-to-self at the time; the SPEC now closes it.

**And the current implementation has a real bug, now verified.** `rfkill`
only governs radio transmitters. On this machine `rfkill list` reports
exactly three entries — `tpacpi_bluetooth_sw`, `phy0` (Wireless LAN), and
`hci0` (Bluetooth) — and **no Ethernet**, while `/sys/class/net/` contains
`enp0s31f6`. So `rfkill block all` **silently does nothing to a wired
connection**: the toggle reports "offline" and the machine stays fully
online. For a feature whose entire purpose is the guarantee that you are
off the network, a silent no-op is the worst possible failure mode.

`toggle-offline.sh` therefore needs to combine `rfkill block all` with
`nmcli networking off`, and should tear the VPN toggles down first — `wg0`
is a raw `wg-quick` interface outside NetworkManager's view, so it would
otherwise be left dangling. Full analysis in `05-network-tunnels.md` §5.

It also needs the safety review a widget function can't express:
`rfkill block all` takes bluetooth input devices with it, so on a laptop
driven by a BT keyboard/mouse this can leave the machine hard to operate.
Whether that is acceptable is the owner's call.

### 5c. `Network.qml` — bluetooth power inline

```qml
function toggleBluetooth() {
  Quickshell.execDetached(["bluetoothctl", "power", btPowered ? "off" : "on"])
  Qt.callLater(refreshAll)
}
```

Straightforward `toggle_main` candidate: `check` is
`bluetoothctl show | grep -q 'Powered: yes'` (already written inline in the
widget's polling `Process`), `on`/`off` are `bluetoothctl power on|off`.
This one is a near-mechanical extraction.

**Refinement after verifying the installed Quickshell version.** This
machine runs quickshell **0.3.1**, which ships native
`/usr/lib/qt6/qml/Quickshell/Bluetooth` and
`/usr/lib/qt6/qml/Quickshell/Networking` modules (both confirmed present on
disk; neither existed in v0.1.0, and neither appears on the stale cached
docs site — see `01-ecosystem-survey.md` on pre-1.0 API churn).

That splits this cleanly along the contract's own seam, and the split is
the *point* of the contract rather than an exception to it:

- **Reading** state — powered, adapters, paired devices, connection status —
  should come from the native `Quickshell.Bluetooth` binding. It replaces a
  polling `Process` that shells out to `bluetoothctl` and greps text, with
  structured properties and change signals. Strictly better: no process
  spawn per poll, no text parsing, live updates instead of a timer.
- **Mutating** persistent state — powering the adapter on/off — still goes
  through `toggles/toggle-bluetooth.sh`, because `menu.sh`, a keybind, and
  herdr must be able to do the same thing without quickshell running.

The same split applies to `Quickshell.Networking` versus the `nmcli`-based
helper scripts, and is worth applying broadly: **native bindings for read,
toggle scripts for write.** Note this is a version-sensitive dependency —
if these modules move or rename before 1.0, the read path breaks while the
toggle scripts keep working, which is itself an argument for the split.

### 5d. `Display.qml` — monitor scale is runtime-only and lossy

```qml
function setMonitorScale(name, scale) {
  Quickshell.execDetached(["bash", "-lc", "hyprctl keyword monitor " + name + ",preferred,auto," + scale])
}
```

Two issues. First, it does not persist — the file's comment says this was
deliberate ("reversible with `hyprctl reload` rather than editing the
actual config … deliberately cautious after the HDMI monitor debugging"),
which was sound caution but leaves the SPEC's "screen scale" only
half-implemented, since it reverts on reload. Second, `preferred,auto`
**discards the monitor's configured resolution, refresh rate, and
position** — on a multi-monitor setup this can rearrange the desktop as a
side effect of nudging a scale.

**Fix:** `toggles/toggle-monitor-scale.sh` that (a) reads the monitor's
current mode from `hyprctl monitors -j` and reapplies it *with* the new
scale rather than `preferred,auto`, and (b) persists into
`configs/hyprland/hyprland_monitors.lua`. Persisting means a Lua-aware
edit, so the script — not a QML regex — is unquestionably the right owner.
Keep the caution: the script should apply at runtime first and only persist
on confirmation, so a bad scale is still recoverable.

## 6. Blocking constraint: the font-token split

Before *any* font selection ships, resolve this.

`Commons/Style.qml:143` pins:

```qml
property string fontFamily: "0xProto Nerd Font"
```

and exposes exactly one token, `Style.font.family`, used for **both body
text and every icon glyph in the bar**. The file's own comment explains the
pin: fall back to another font and a Nerd Font codepoint renders as a
completely different glyph, and the `l-quickshell` skill notes several past
bugs were exactly this.

So "any installed font" applied to `Style.fontFamily` would silently break
every icon in the shell. The design must split the token first:

- `Style.font.ui` — user-selectable, what SPEC's font picker changes
- `Style.font.icon` — stays pinned to `0xProto Nerd Font`, never
  user-facing

and every glyph call site must be moved to `Style.font.icon`. That is a
sweep across the widget tree and should be its own task, sequenced *before*
`toggle-font.sh` gains the ability to touch quickshell.

A softer option worth offering in the picker UI: filter `fc-list` to
families that actually contain the Nerd Font private-use range, so the user
can only pick fonts where icons survive. Good middle ground, but it does
not remove the need for the split — body and icon text still want different
metrics.

## 7. Implementation order

1. `toggle-bluetooth.sh` — mechanical extraction, no design risk.
2. `toggle-offline.sh` — needs the safety decision from
   `05-network-tunnels.md` first.
3. Font-token split in `Commons/Style.qml` + glyph call-site sweep.
4. `toggle-font.sh` (`get|label|list|set|set-size`) covering ghostty, zed
   (all three pairs), emacs, discord, nvim, waybar, quickshell.
5. `toggle-monitor-scale.sh` with mode-preserving apply + Lua persistence.
6. Give `switch-wallpaper.sh` a `get|list|set` CLI so a native picker can
   drive it instead of launching an external one.

Steps 1-2 are self-contained. Steps 3-4 are one unit — do not ship 4
without 3.
