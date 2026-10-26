# Graphics tablet (SZ PENG YI T1161, USB `08f2:6811`)

No kernel driver handles this pad, so `tablet-driver.py` reads it over hidraw and republishes a clean uinput tablet.
udev (`71-graphics-tablet.rules`) hides the kernel's nodes and starts `tablet-driver.service` on plug-in.

Why userspace:

- It boots in a shrunken mode; a feature handshake on report 8 toggles modes (not idempotent, not readable), so the
  driver always sends it and re-toggles when the reports have the wrong format.
- Two pen interfaces share one name; the dead one wins the plain name.
- X only spans 16384..32767; the driver rescales it.
- It rarely reports pen-lift: silence longer than `PROXIMITY_TIMEOUT_S` counts as lift.
- Pressure can't tell hover from contact: pressure follows the tip switch.
- The 14 buttons arrive only in vendor report 1, which no kernel driver decodes.

Buttons (report 1, interface 2, `01 80 <in range> 00 <mask4> <mask5> 00 00`, momentary bitmap):

| bits | published as |
|---|---|
| `mask5 0x20`, `0x10` | `BTN_STYLUS`, `BTN_STYLUS2` on the pen |
| `mask4 0x01..0x80` | `F13..F20` on `SDD Tablet T1161 Keys` |
| `mask5 0x01..0x08` | `F21..F24` on the same keyboard |

Bit order may not match the physical layout: press each key and watch the F-code. Bind them like any key, e.g.
`hl.bind("F13", hl.dsp.exec_cmd("..."))` in `hyprland_keybindings.lua`.

Check:

```bash
./test-driver.py                     # offline decode test, run after any driver change
systemctl status tablet-driver
./verify-mapping.py 30 DP-2          # sweep the whole pad
libinput list-devices | grep '^Device.*T1161'   # exactly two virtual devices
```

Calibrate (writes `/var/lib/tablet-driver/calibration.json`, delete it for the defaults):

```bash
sudo systemctl stop tablet-driver && sudo ./tablet-driver.py --calibrate 20 && sudo systemctl start tablet-driver
```

Gotchas:

- The output mapping is `input:tablet:output` in `hyprland_input.lua`, global, never per device (`-1` suffixes move).
- `hyprctl keyword` fails on the Lua config; use `hyprctl eval` or edit the Lua.
- In udev, `ATTRS`/`KERNELS` keys must match one parent; libinput unions `ID_INPUT_*` of the event node and its parent.
- After a rules change, reload is not enough and `USBDEVFS_RESET` keeps the old nodes: unbind and rebind the usbhid
  interfaces (or replug), then restart the driver.
- OpenTabletDriver's modprobe.d file neuters `hid_uclogic` and `wacom`; uninstall it.
- The fake "Internal CDROM" (Windows driver) is hidden from udisks.
