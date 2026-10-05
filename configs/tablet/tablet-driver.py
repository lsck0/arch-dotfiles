#!/usr/bin/env python3
"""Userspace driver for the SZ PENG YI [T1161] "Driver Inside" tablet (08f2:6811).

Why this exists
---------------
The kernel cannot drive this pad usefully on its own:

  * Out of reset the device sits in a shrunken "sleep mode" and reports the pen
    on USB interface 2 (report id 5, 0..4095) using only a fraction of the
    surface.  hid-uclogic cannot unlock it -- every UC-Logic magic string
    descriptor STALLs on this unit.
  * A vendor feature handshake on interface 2 (report id 8) switches it into its
    real mode, where the pen moves to *interface 1* as report id 9 at 0..32767.
  * Even then the firmware squeezes the X axis into the *upper half* of its own
    declared logical range: the left edge of the pad reads ~16384 and the right
    edge ~32767, while Y correctly spans 0..32767.  The kernel believes the
    descriptor, so half of the mapped screen is physically unreachable.

So we read the HID reports ourselves, rescale X, and republish the pen as a
clean uinput tablet whose axes really do span their full declared range.  The
compositor then maps it bijectively onto one output with no tricks.

Run it as root (it needs hidraw + /dev/uinput).  It exits when the tablet is
unplugged; the systemd unit restarts it when it comes back.
"""

from __future__ import annotations

import argparse
import ctypes
import errno
import fcntl
import glob
import json
import os
import select
import struct
import sys
import time

VENDOR = 0x08F2
PRODUCT = 0x6811
HID_ID = f"0003:{VENDOR:08X}:{PRODUCT:08X}"

PEN_REPORT_ID = 9
PEN_REPORT_LEN = 10

# buttons arrive on interface 2 as opaque vendor report id 1 (no kernel driver decodes it); payload `01 80 <in range> 00 <mask4> <mask5> 00 00`, the mask bytes a momentary press/release bitmap
BUTTON_REPORT_ID = 1
BUTTON_REPORT_LEN = 8

# the only stylus buttons: the barrel and eraser bits in pen report id 9 are never set by this device
PEN_BUTTON_BITS = {
    (5, 0x20): "BTN_STYLUS",   # lower
    (5, 0x10): "BTN_STYLUS2",  # upper
}

# 12 express keys published as F13..F24, keycodes no keyboard emits so they bind without collision; order is bit order not physical, rebind to taste
EXPRESS_KEY_BITS = [
    (4, 0x01), (4, 0x02), (4, 0x04), (4, 0x08),
    (4, 0x10), (4, 0x20), (4, 0x40), (4, 0x80),
    (5, 0x01), (5, 0x02), (5, 0x04), (5, 0x08),
]
EXPRESS_KEY_NAMES = [f"KEY_F{n}" for n in range(13, 25)]

# report id 9 status byte, per the device descriptor: bit0 tip, bit1 barrel, bit2 eraser, bit6 in range
TIP_BIT = 0x01
BARREL_BIT = 0x02
ERASER_BIT = 0x04
IN_RANGE_BIT = 0x40

# pad rarely signals pen-lift (1 of 7470 reports), it just stops reporting; in range it streams ~300 Hz, so a silence past 200 ms (~60 frames, still imperceptible) is a reliable lift
PROXIMITY_TIMEOUT_S = 0.2

# unrecognised pen reports tolerated before re-toggling the pen mode (~300 Hz, a fraction of a second in use); MAX_RETOGGLES stops a pad that speaks neither format toggling forever
WRONG_MODE_LIMIT = 100
MAX_RETOGGLES = 6

# Firmware limits of the *raw* axes, as measured on the wire.
RAW_MAX = 32767
PRESSURE_MAX = 16383

# raw pressure cannot tell contact from hover (hover=29, light touch=11), so republish from the tip switch: 0 hovering, >= TIP_FLOOR in contact so pressure-threshold consumers agree with the tip bit
TIP_FLOOR = 1638  # 10% of PRESSURE_MAX, above libinput's 5% tip threshold

# Physical active area from the interface-2 descriptor, in millimetres.
AREA_W_MM = 205.0
AREA_H_MM = 137.0

# Axis range we publish.  Independent of what the firmware happens to use.
OUT_MAX = 32767

# default calibration: the firmware's usable X window; `--calibrate` measures the real one into CALIB_PATH, which then wins
DEFAULT_CALIB = {"x_min": 16384, "x_max": 32767, "y_min": 0, "y_max": 32767}
CALIB_PATH = "/var/lib/tablet-driver/calibration.json"

# six-command handshake leaving sleep mode, byte 0 is the report id; sent as HID feature reports (hidraw equivalent of the Windows driver's SET_REPORT(0x0308)), no interface claim needed
UNLOCK_COMMANDS = [
    bytes([0x08, 0x03, 0xFC, 0x03, 0x87, 0x00, 0xFF, 0xF0]),
    bytes([0x08, 0x07, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF]),
    bytes([0x08, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
    bytes([0x08, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
    bytes([0x08, 0x06, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00]),
    bytes([0x08, 0x01, 0xFC, 0x03, 0x87, 0x00, 0xFF, 0xF0]),
]
UNLOCK_GAP_S = 0.05  # back-to-back commands leave the device in sleep mode


def log(msg: str) -> None:
    print(msg, flush=True)


# --------------------------------------------------------------------------
# device discovery
# --------------------------------------------------------------------------


def find_hidraw(interface: str) -> str | None:
    """Return the hidraw node of our tablet on the given USB interface number."""
    for node in sorted(glob.glob("/dev/hidraw*")):
        sysfs = "/sys/class/hidraw/" + os.path.basename(node) + "/device"
        try:
            if HID_ID not in open(sysfs + "/uevent").read():
                continue
            usb_iface = os.path.dirname(os.path.realpath(sysfs))
            if open(usb_iface + "/bInterfaceNumber").read().strip() == interface:
                return node
        except OSError:
            continue
    return None


def wait_for_hidraw(interface: str, timeout: float) -> str | None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        node = find_hidraw(interface)
        if node:
            return node
        time.sleep(0.25)
    return None


# --------------------------------------------------------------------------
# unlock
# --------------------------------------------------------------------------


def hidiocsfeature(length: int) -> int:
    # _IOC(_IOC_READ|_IOC_WRITE, 'H', 0x06, length)
    return (3 << 30) | (length << 16) | (ord("H") << 8) | 0x06


def unlock(node: str) -> bool:
    """Send the handshake that takes the pad out of its shrunken sleep mode.

    This is a *toggle*, not an unlock, which is easy to get wrong because
    every command is accepted every time. From the power-on state the first
    handshake gives the pen on interface 1 as report id 9, which is the only
    format this driver speaks. A second one does not re-confirm that: it
    advances to another mode where interface 1 sends a big-endian report id 6
    instead, which looks exactly like a dead tablet while every layer reports
    healthy. A third brings report 9 back.

    A USB reset does not help -- it reattaches the device with its mode
    intact, so resetting before the handshake guarantees a flip on every
    restart rather than preventing one. The only reliable approach is to look
    at what the pen actually sends and toggle again if it is wrong, which
    run() does.
    """
    try:
        fd = os.open(node, os.O_RDWR)
    except OSError as exc:
        log(f"unlock: cannot open {node}: {exc}")
        return False
    try:
        for cmd in UNLOCK_COMMANDS:
            buf = ctypes.create_string_buffer(cmd, len(cmd))
            try:
                fcntl.ioctl(fd, hidiocsfeature(len(cmd)), buf)
            except OSError as exc:
                log(f"unlock: command {cmd.hex(' ')} failed: {exc}")
                return False
            time.sleep(UNLOCK_GAP_S)
    finally:
        os.close(fd)
    log(f"unlock: handshake accepted on {node}")
    return True


# --------------------------------------------------------------------------
# uinput tablet
# --------------------------------------------------------------------------


def make_uinput(calib: dict):
    from evdev import AbsInfo, UInput
    from evdev import ecodes as e

    # Resolution in units per mm, so userspace sees a sane physical size.
    res_x = round(OUT_MAX / AREA_W_MM)
    res_y = round(OUT_MAX / AREA_H_MM)

    caps = {
        e.EV_KEY: [
            e.BTN_TOOL_PEN,
            e.BTN_TOOL_RUBBER,
            e.BTN_TOUCH,
            e.BTN_STYLUS,
            e.BTN_STYLUS2,
        ],
        e.EV_ABS: [
            (e.ABS_X, AbsInfo(0, 0, OUT_MAX, 0, 0, res_x)),
            (e.ABS_Y, AbsInfo(0, 0, OUT_MAX, 0, 0, res_y)),
            (e.ABS_PRESSURE, AbsInfo(0, 0, PRESSURE_MAX, 0, 0, 0)),
            (e.ABS_TILT_X, AbsInfo(0, -127, 127, 0, 0, 0)),
            (e.ABS_TILT_Y, AbsInfo(0, -127, 127, 0, 0, 0)),
        ],
    }
    ui = UInput(
        caps,
        name="SDD Tablet T1161",
        vendor=VENDOR,
        product=PRODUCT,
        version=2,
        bustype=0x03,  # BUS_USB, so udev classifies it like a real tablet
        input_props=[e.INPUT_PROP_DIRECT],
    )
    # ui.device scans /dev/input for the new node and races udev creating it; not worth waiting for, it is only a label
    node = getattr(getattr(ui, "device", None), "path", None) or "pending"
    log(f"uinput: created {ui.name} at {node}")
    log(
        "uinput: X raw {x_min}..{x_max} -> 0..{m}, Y raw {y_min}..{y_max} -> 0..{m}".format(
            m=OUT_MAX, **calib
        )
    )
    return ui


def make_keys_uinput():
    """Second virtual device for the 12 pad express keys.

    They are deliberately kept off the tablet device: libinput would classify
    extra keys on a BUS_USB tablet as a tablet *pad*, whose events only reach
    an application that has grabbed the pad. As a plain keyboard the keys go
    through the compositor's normal keybinding path instead.
    """
    from evdev import UInput
    from evdev import ecodes as e

    caps = {e.EV_KEY: [getattr(e, name) for name in EXPRESS_KEY_NAMES]}
    ui = UInput(
        caps,
        name="SDD Tablet T1161 Keys",
        vendor=VENDOR,
        product=PRODUCT,
        version=2,
        bustype=0x03,
    )
    node = getattr(getattr(ui, "device", None), "path", None) or "pending"
    log(f"uinput: created {ui.name} at {node} ({len(EXPRESS_KEY_NAMES)} keys)")
    return ui


def scale(value: int, lo: int, hi: int) -> int:
    if hi <= lo:
        return 0
    return max(0, min(OUT_MAX, round((value - lo) * OUT_MAX / (hi - lo))))


def pressure_for(tip_down: bool, raw: int) -> int:
    """Republish pressure as a function of the tip switch.

    The raw value is useless on its own here: hovering reports a constant 29
    and a light touch can report 11, so no threshold can separate them. The
    tip switch can, so it decides, and the raw value only shapes how hard the
    contact is within the contact range.
    """
    if not tip_down:
        return 0
    raw = max(0, min(raw, PRESSURE_MAX))
    return TIP_FLOOR + round(raw * (PRESSURE_MAX - TIP_FLOOR) / PRESSURE_MAX)


# --------------------------------------------------------------------------
# calibration
# --------------------------------------------------------------------------


def load_calibration(path: str) -> dict:
    calib = dict(DEFAULT_CALIB)
    try:
        with open(path) as fh:
            stored = json.load(fh)
        for key in DEFAULT_CALIB:
            if isinstance(stored.get(key), int):
                calib[key] = stored[key]
        log(f"calibration: loaded {path} -> {calib}")
    except FileNotFoundError:
        log(f"calibration: {path} absent, using defaults {calib}")
    except (OSError, ValueError) as exc:
        log(f"calibration: ignoring unreadable {path}: {exc}")
    return calib


def save_calibration(path: str, calib: dict) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(calib, fh, indent=2, sort_keys=True)
        fh.write("\n")
    os.replace(tmp, path)
    log(f"calibration: wrote {path}")


def read_pen_reports(fd: int, duration: float):
    """Yield (status, x, y, pressure, tilt_x, tilt_y) for `duration` seconds."""
    deadline = time.time() + duration
    while time.time() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.2)
        if not ready:
            continue
        try:
            data = os.read(fd, 64)
        except OSError as exc:
            if exc.errno in (errno.EAGAIN, errno.EINTR):
                continue
            raise
        if not data or data[0] != PEN_REPORT_ID or len(data) < 8:
            continue
        status = data[1]
        x, y, pressure = struct.unpack_from("<HHH", data, 2)
        tilt_x = struct.unpack_from("b", data, 8)[0] if len(data) > 8 else 0
        tilt_y = struct.unpack_from("b", data, 9)[0] if len(data) > 9 else 0
        yield status, x, y, pressure, tilt_x, tilt_y


def calibrate(node: str, duration: float, path: str) -> int:
    log(f"calibration: sweep the whole pad for {duration:.0f}s, edges included")
    fd = os.open(node, os.O_RDONLY | os.O_NONBLOCK)
    xs: list[int] = []
    ys: list[int] = []
    try:
        for status, x, y, _p, _tx, _ty in read_pen_reports(fd, duration):
            if not status & IN_RANGE_BIT:
                continue
            xs.append(x)
            ys.append(y)
    finally:
        os.close(fd)
    if len(xs) < 200:
        log(f"calibration: only {len(xs)} samples, refusing to guess")
        return 1
    calib = {"x_min": min(xs), "x_max": max(xs), "y_min": min(ys), "y_max": max(ys)}
    span_x = calib["x_max"] - calib["x_min"]
    span_y = calib["y_max"] - calib["y_min"]
    log(f"calibration: {len(xs)} samples, X {calib['x_min']}..{calib['x_max']} "
        f"(span {span_x}), Y {calib['y_min']}..{calib['y_max']} (span {span_y})")
    if span_x < 4096 or span_y < 4096:
        log("calibration: span too small, the pad was not swept fully")
        return 1
    save_calibration(path, calib)
    return 0


# --------------------------------------------------------------------------
# main loop
# --------------------------------------------------------------------------


def run(node: str, calib: dict) -> int:
    from evdev import ecodes as e

    ui = make_uinput(calib)
    ui_keys = make_keys_uinput()
    fd = os.open(node, os.O_RDONLY | os.O_NONBLOCK)
    log(f"driver: reading pen on {node}")

    # buttons live on the other interface (alive after unlock); losing it costs the buttons but not the pen, so never fatal
    btn_node = find_hidraw("02")
    btn_fd = -1
    if btn_node:
        try:
            btn_fd = os.open(btn_node, os.O_RDONLY | os.O_NONBLOCK)
            log(f"driver: reading buttons on {btn_node}")
        except OSError as exc:
            log(f"driver: cannot open {btn_node} ({exc}); buttons disabled")
    else:
        log("driver: interface 2 not found; buttons disabled")

    express_codes = [getattr(e, name) for name in EXPRESS_KEY_NAMES]
    pen_button_codes = {bit: getattr(e, name) for bit, name in PEN_BUTTON_BITS.items()}

    in_proximity = False
    last_report = 0.0
    last = {}
    key_mask = 0
    wrong_mode = 0
    retoggles = 0

    def emit(code_type, code, value):
        if last.get((code_type, code)) == value:
            return
        last[(code_type, code)] = value
        ui.write(code_type, code, value)

    def leave_proximity():
        """Put the tool down cleanly. Also used when the pad just goes quiet."""
        emit(e.EV_KEY, e.BTN_TOUCH, 0)
        emit(e.EV_ABS, e.ABS_PRESSURE, 0)
        emit(e.EV_KEY, e.BTN_STYLUS, 0)
        emit(e.EV_KEY, e.BTN_STYLUS2, 0)
        emit(e.EV_KEY, e.BTN_TOOL_PEN, 0)
        emit(e.EV_KEY, e.BTN_TOOL_RUBBER, 0)
        ui.syn()

    def release_keys():
        nonlocal key_mask
        if not key_mask:
            return
        for index, code in enumerate(express_codes):
            if key_mask & (1 << index):
                ui_keys.write(e.EV_KEY, code, 0)
        ui_keys.syn()
        key_mask = 0

    def handle_buttons(data):
        """Decode report id 1 into stylus buttons and pad keys."""
        nonlocal key_mask

        pen_changed = False
        for (offset, bit), code in pen_button_codes.items():
            value = 1 if data[offset] & bit else 0
            if last.get((e.EV_KEY, code)) != value:
                emit(e.EV_KEY, code, value)
                pen_changed = True
        if pen_changed:
            ui.syn()

        mask = 0
        for index, (offset, bit) in enumerate(EXPRESS_KEY_BITS):
            if data[offset] & bit:
                mask |= 1 << index
        if mask == key_mask:
            return
        for index, code in enumerate(express_codes):
            was, now = key_mask & (1 << index), mask & (1 << index)
            if bool(was) != bool(now):
                ui_keys.write(e.EV_KEY, code, 1 if now else 0)
        ui_keys.syn()
        key_mask = mask

    try:
        while True:
            watch = [fd] + ([btn_fd] if btn_fd >= 0 else [])
            # block until a report arrives, with a deadline only while the pen is in range to catch its silent lift
            timeout = max(0.0, last_report + PROXIMITY_TIMEOUT_S - time.monotonic()) if in_proximity else None
            ready, _, _ = select.select(watch, [], [], timeout)

            if btn_fd in ready:
                try:
                    data = os.read(btn_fd, 64)
                    if not data:
                        # same EOF trap as the pen node below: select() keeps reporting it readable forever
                        log("driver: button node reached end of file; "
                            "buttons disabled")
                        release_keys()
                        os.close(btn_fd)
                        btn_fd = -1
                    elif data[0] == BUTTON_REPORT_ID and len(data) >= BUTTON_REPORT_LEN:
                        handle_buttons(data)
                except OSError as exc:
                    if exc.errno not in (errno.EAGAIN, errno.EINTR):
                        log(f"driver: button read failed ({exc}); buttons disabled")
                        release_keys()
                        os.close(btn_fd)
                        btn_fd = -1

            if fd not in ready:
                if in_proximity and time.monotonic() - last_report > PROXIMITY_TIMEOUT_S:
                    in_proximity = False
                    leave_proximity()
                if not os.path.exists(node):
                    log("driver: device went away")
                    return 0
                continue

            try:
                data = os.read(fd, 64)
            except OSError as exc:
                if exc.errno in (errno.EAGAIN, errno.EINTR):
                    continue
                log(f"driver: read failed ({exc}), device probably unplugged")
                if in_proximity:
                    leave_proximity()
                return 0
            if not data:
                # a vanished hidraw node raises ENODEV above; an empty read means the other end closed, and select() keeps reporting EOF readable so continuing would spin at full tilt
                log("driver: pen node reached end of file")
                if in_proximity:
                    leave_proximity()
                return 0
            if len(data) < PEN_REPORT_LEN:
                continue
            if data[0] != PEN_REPORT_ID:
                # pen in the format we do not speak: the handshake toggled one step too far (see unlock()); hidraw nodes survive a handshake, so toggle again and carry on
                wrong_mode += 1
                if wrong_mode < WRONG_MODE_LIMIT:
                    continue
                wrong_mode = 0
                if retoggles >= MAX_RETOGGLES or btn_node is None:
                    continue
                retoggles += 1
                log(f"driver: interface 1 is sending report id {data[0]}, not "
                    f"{PEN_REPORT_ID}; re-toggling the pen mode "
                    f"({retoggles}/{MAX_RETOGGLES})")
                unlock(btn_node)
                continue

            if wrong_mode or retoggles:
                wrong_mode = 0
                retoggles = 0
            last_report = time.monotonic()
            status = data[1]
            raw_x, raw_y, raw_pressure = struct.unpack_from("<HHH", data, 2)
            tilt_x = struct.unpack_from("b", data, 8)[0]
            tilt_y = struct.unpack_from("b", data, 9)[0]

            if not status & IN_RANGE_BIT:
                if in_proximity:
                    in_proximity = False
                    leave_proximity()
                continue

            in_proximity = True
            tip_down = bool(status & TIP_BIT)
            eraser = bool(status & ERASER_BIT)

            emit(e.EV_KEY, e.BTN_TOOL_PEN, 0 if eraser else 1)
            emit(e.EV_KEY, e.BTN_TOOL_RUBBER, 1 if eraser else 0)

            emit(e.EV_ABS, e.ABS_X, scale(raw_x, calib["x_min"], calib["x_max"]))
            emit(e.EV_ABS, e.ABS_Y, scale(raw_y, calib["y_min"], calib["y_max"]))
            emit(e.EV_ABS, e.ABS_PRESSURE, pressure_for(tip_down, raw_pressure))
            emit(e.EV_ABS, e.ABS_TILT_X, tilt_x)
            emit(e.EV_ABS, e.ABS_TILT_Y, tilt_y)
            emit(e.EV_KEY, e.BTN_TOUCH, 1 if tip_down else 0)
            ui.syn()
    except KeyboardInterrupt:
        return 0
    finally:
        release_keys()
        if btn_fd >= 0:
            os.close(btn_fd)
        os.close(fd)
        ui_keys.close()
        ui.close()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--calibrate", type=float, metavar="SECONDS", nargs="?",
                    const=20.0, help="measure the usable axis range and store it")
    ap.add_argument("--calibration", default=CALIB_PATH, help="calibration file path")
    ap.add_argument("--wait", type=float, default=15.0,
                    help="seconds to wait for the device to appear")
    ap.add_argument("--no-unlock", action="store_true",
                    help="skip the sleep-mode handshake")
    args = ap.parse_args()

    if not args.no_unlock:
        iface2 = wait_for_hidraw("02", args.wait)
        if not iface2:
            log("no tablet on USB interface 2; is it plugged in?")
            return 1
        unlock(iface2)
        # The pen only migrates to interface 1 once the handshake lands.
        time.sleep(0.3)

    iface1 = wait_for_hidraw("01", args.wait)
    if not iface1:
        log("no tablet on USB interface 1 after unlock")
        return 1

    if args.calibrate is not None:
        return calibrate(iface1, args.calibrate, args.calibration)

    return run(iface1, load_calibration(args.calibration))


if __name__ == "__main__":
    sys.exit(main())
