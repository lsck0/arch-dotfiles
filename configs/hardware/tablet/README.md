# Graphics tablet (SZ PENG YI [T1161], USB `08f2:6811`)

A "driver inside" pad that no kernel driver handles correctly, so
`tablet-driver.py` drives it from userspace and republishes the pen as a
virtual tablet. `system.sh` installs it; `config.sh` picks that up automatically.

```
tablet-driver.py     the driver; also sends the unlock handshake
tablet-driver.service started by udev when the pad is plugged in
71-graphics-tablet.rules  suppresses the kernel's own nodes, starts the driver
verify-mapping.py    measures where the pen actually puts the cursor
```

## Why a userspace driver

Six separate faults stack up, and the first two hide the rest:

1. **The pad boots into a shrunken "sleep mode."** The pen appears on USB
   interface 2 (report id 5, axes 0..4095) and only part of the surface
   senses. A vendor feature handshake on report id 8 switches it into its
   real mode, after which the pen moves to **interface 1** (report id 9, axes
   0..32767) and interface 2 goes silent. `hid-uclogic` cannot do this: every
   UC-Logic magic string descriptor STALLs on this unit.

   The handshake is a **toggle, not an unlock**, which is a trap: all six
   commands are accepted every time, so it looks idempotent. From the
   power-on state the first one gives report id 9; a second advances to a
   *third* mode where interface 1 sends a big-endian report id 6 instead, and
   a third brings report 9 back. In mode 6 the driver sees nothing it
   recognises, so the tablet is dead while systemd, udev, libinput and the
   driver's own log all look perfectly healthy. Restarting the service with
   the pad plugged in is enough to land in it.

   A USB reset does **not** undo this: the device comes back with its mode
   intact. Nor can the mode be read back: report id 8 is write-only, so
   `HIDIOCGFEATURE` on it returns `EINVAL`. So the driver does not try to
   reach a known state, it watches what the pen actually sends and toggles
   again when the format is wrong.

   It therefore always sends the handshake at startup, even though that
   flips a pad that was already correct. That is deliberate: a wrong mode
   produces *reports*, which can be detected and corrected, whereas skipping
   the handshake on a pad that turned out to be asleep produces **silence**,
   which is indistinguishable from a pen nobody is holding. The cost is that
   a restart with the pad plugged in needs about a third of a second of pen
   movement before it corrects itself.
2. **Two pen interfaces, one name.** libinput accepts both, so the compositor
   sees two tablets with the identical name and appends `-1` to whichever it
   enumerates second. The dead one sorts first and takes the plain name, so a
   mapping rule written against the obvious name lands on a pen that never
   moves. Interface 1 also exposes a relative mouse that fights the pen.
3. **The firmware lies about its own X range.** It declares 0..32767 but only
   ever emits 16384..32767: the left edge of the pad reads ~16384 and the
   right edge ~32767, while Y correctly spans the full range. Map that device
   to an output and half the screen is physically unreachable, which looks
   exactly like a clamped mapping.
4. **It almost never announces pen-lift.** Across 7470 captured reports it sent
   an out-of-range status exactly *once*; normally it just stops reporting.
   Taken literally that freezes the tip in whatever state it last had, so
   lifting mid-stroke leaves the tip logically down and the next touch draws a
   line joining the two points. The driver treats a silence longer than
   `PROXIMITY_TIMEOUT_S` as a lift, which is safe because the pad streams
   continuously at ~300 Hz for as long as the pen is in range.
5. **Pressure cannot distinguish contact from hover.** Hovering reports a
   constant 29 while a light touch can report 11, so no threshold separates
   them. Only the tip switch is trustworthy, so the driver republishes
   pressure as a function of it: exactly 0 while hovering, and never below
   `TIP_FLOOR` while in contact, so anything downstream that derives tip state
   from a pressure threshold agrees with the tip bit.
6. **No kernel driver decodes the buttons.** None of the 14 buttons travel
   with the pen. They arrive on interface 2 as vendor report id 1, an opaque
   collection the kernel hands to nobody, so without this driver all of them
   are simply dead. Worse, a few of them *also* emit canned keystrokes through
   the pad's keyboard and consumer collections, which the kernel *does* expose
   so one express key muted the machine while doing nothing else useful.
   The udev rule suppresses those nodes and the driver republishes all 14 from
   the vendor report instead.

The driver reads interface 1 over hidraw, rescales X onto the full range, and
emits a clean uinput tablet. Only then is a bijective output mapping possible,
which `configs/desktop/hyprland/hyprland_input.lua` sets with `input:tablet:output`.

## Buttons

Report id 1 on interface 2 is `01 80 <pen in range> 00 <mask4> <mask5> 00 00`.
The two mask bytes are a plain momentary bitmap: a press sets its bit, a
release clears it, and letting go of everything sends an all-zero mask.

| bits | count | published as | on device |
| --- | --- | --- | --- |
| `mask5` `0x20` | 1 | `BTN_STYLUS` | `SDD Tablet T1161` (pen) |
| `mask5` `0x10` | 1 | `BTN_STYLUS2` | `SDD Tablet T1161` (pen) |
| `mask4` `0x01`..`0x80` | 8 | `F13`..`F20` | `SDD Tablet T1161 Keys` |
| `mask5` `0x01`..`0x08` | 4 | `F21`..`F24` | `SDD Tablet T1161 Keys` |

The pen buttons go on the tablet device so drawing applications treat them as
stylus buttons. The 12 express keys go on a *separate virtual keyboard*
instead: extra keys on a `BUS_USB` tablet would make libinput classify it as a
tablet *pad*, whose events only reach an application that has grabbed the pad,
whereas plain keys go through the compositor's normal keybinding path. `F13`
to `F24` are real keycodes that no keyboard emits on its own, so nothing
collides. Bind them in Hyprland like any other key:

```lua
bind = { "", "F13", "exec", "..." }
```

Bit order is not guaranteed to match the physical layout: press each key once
and watch which F-code appears.

## Checking it

```bash
./test-driver.py                # offline: no tablet needed, ~1 min

systemctl status tablet-driver
./verify-mapping.py 30 DP-2     # sweep the whole pad while it runs

# what the compositor actually gets, including tip and proximity
libinput debug-events --device /dev/input/by-id/... | grep TABLET_TOOL

# exactly two devices, both virtual: the kernel's six nodes must all be gone
libinput list-devices | grep '^Device.*T1161'
```

`test-driver.py` feeds recorded report bytes through a pair of FIFOs, so the
whole decode path (axis mapping, tip and pressure, pen-lift, all 14 buttons
and the wrong-mode recovery) is checked without touching the hardware. Run it
after any change to the driver; several of these faults are invisible until a
pen is physically in range, which makes them miserable to test by hand.

`verify-mapping.py` reconstructs the whole transfer function rather than
comparing extremes, because a clamped or folded mapping still reaches both
screen edges. It says "inconclusive" when the pad was not swept fully: a
range check alone would have called this tablet healthy while half of it was
dead.

A healthy lift shows `proximity-out` within ~200 ms of the pen leaving the
pad. If strokes join up across lifts, that event is missing.

## Calibration

The driver defaults to the firmware's observed window, `x 16384..32767`,
`y 0..32767`, which measures bijective. To re-measure:

```bash
sudo systemctl stop tablet-driver
sudo ./tablet-driver.py --calibrate 20     # sweep the whole pad, edges included
sudo systemctl start tablet-driver
```

That writes `/var/lib/tablet-driver/calibration.json`, which then wins over
the defaults. Delete the file to go back to them.

## Gotchas

- `hyprctl keyword` is a **no-op** on this machine: the Hyprland config is Lua,
  and the Lua parser rejects it with *"keyword can't work with non-legacy
  parsers."* Use `hyprctl eval` or edit the Lua. Every online guide for tablet
  mapping fails silently here for this reason.
- Set the tablet mapping **globally**, never per device. The `-1` suffixes
  follow enumeration order and are not stable.
- In a udev rule, all `ATTRS`/`KERNELS`/`SUBSYSTEMS`/`DRIVERS` keys must match
  one and the same parent, so `bInterfaceNumber` (USB interface) cannot be
  combined with `idVendor` (USB device). `ENV{}` keys are read off the device
  itself and are exempt.
- libinput reads `ID_INPUT_*` from the event node **and** its parent `input*`
  node and takes the union, so both have to be cleared.
- The rules file must sort after `60-input-id.rules` and before
  `73-seat-late.rules`. Hence `71-`.
- A `USBDEVFS_RESET` ioctl reattaches the pad without clearing its pen mode,
  so it cannot be used to get back to a known state. It also does not re-create
  the input nodes, which is a second trap: see below.
- After changing the rules, `udevadm control --reload` alone is not enough and
  neither is a `USBDEVFS_RESET` ioctl: the reset reattaches the device without
  re-creating its input nodes, so udev replays nothing and the old properties
  stay in the database. `udevadm test` will happily show the new result while
  the live device keeps the old one. Force real `add` events by rebinding the
  interfaces, or just replug:

  ```bash
  for i in <bus>-<port>:1.1 <bus>-<port>:1.2; do
    echo -n $i | sudo tee /sys/bus/usb/drivers/usbhid/unbind
  done   # then the same with .../bind, then restart tablet-driver
  ```
- OpenTabletDriver, if ever installed again, ships
  `/usr/lib/modprobe.d/99-opentabletdriver.conf`, which neuters `hid_uclogic` and
  `wacom` with `install ... /usr/bin/true`. This driver needs neither, but it
  breaks any attempt to go back to a kernel driver. `patches/02` uninstalls it.
- The pad also presents a fake "Internal CDROM" holding the Windows driver;
  the rules hide it from udisks.
