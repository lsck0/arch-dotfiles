#!/usr/bin/env python3
"""Offline tests for tablet-driver.py.

The driver reads its two HID nodes with plain os.open/os.read, so a pair of
FIFOs stands in for the tablet and the whole report-handling path can be
exercised without the hardware -- including the cases that are awkward to
provoke by hand, like the pad waking up in the wrong pen mode.

    ./test-driver.py
"""

import importlib.util
import os
import shutil
import struct
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))

spec = importlib.util.spec_from_file_location("td", os.path.join(HERE, "tablet-driver.py"))
td = importlib.util.module_from_spec(spec)
spec.loader.exec_module(td)

from evdev import ecodes as e  # noqa: E402  (after the driver import, same dep)


class FakeUInput:
    """Records what the driver publishes, in order."""

    def __init__(self, name):
        self.name = name
        self.events = []
        self.device = None

    def write(self, etype, code, value):
        self.events.append((etype, code, value))

    def syn(self):
        pass

    def close(self):
        pass

    def codes(self, etype):
        return [c for t, c, v in self.events if t == etype]

    def values(self, etype, code):
        return [v for t, c, v in self.events if t == etype and c == code]


def pen_report(x, y, pressure, status=td.IN_RANGE_BIT, tilt=(0, 0)):
    return struct.pack("<BBHHHbb", td.PEN_REPORT_ID, status, x, y, pressure, *tilt)


def other_mode_report():
    """A report id 6 frame, the format the driver does not speak."""
    return bytes([6, 0x00, 0xA7, 0x0E, 0x5B, 0x05, 0x3F, 0x06, 0x12, 0x02, 0x05, 0xFF]) + bytes(52)


def button_report(mask4=0, mask5=0):
    return bytes([td.BUTTON_REPORT_ID, 0x80, 0xFF, 0x00, mask4, mask5, 0x00, 0x00])


def drive(pen_frames, button_frames=(), calib=None):
    """Run the driver against FIFOs, feed it frames, return what it published."""
    tmp = tempfile.mkdtemp(prefix="tablet-test-")
    pen_path = os.path.join(tmp, "pen")
    btn_path = os.path.join(tmp, "buttons")
    os.mkfifo(pen_path)
    os.mkfifo(btn_path)

    pen_ui, keys_ui = FakeUInput("pen"), FakeUInput("keys")
    unlocks = []

    orig_find, orig_unlock = td.find_hidraw, td.unlock
    orig_make, orig_make_keys = td.make_uinput, td.make_keys_uinput
    td.find_hidraw = lambda iface: btn_path if iface == "02" else pen_path
    td.unlock = lambda node: (unlocks.append(node), True)[1]
    td.make_uinput = lambda c: pen_ui
    td.make_keys_uinput = lambda: keys_ui

    def feed(path, frames):
        # Opening for write blocks until the driver opens the read end.
        with open(path, "wb", buffering=0) as handle:
            for frame in frames:
                handle.write(frame)
                time.sleep(0.0005)
            # Let the driver drain, then make the node vanish so run() returns.
            time.sleep(1.0)
            if path == pen_path:
                os.unlink(pen_path)

    threads = [threading.Thread(target=feed, args=(pen_path, pen_frames), daemon=True),
               threading.Thread(target=feed, args=(btn_path, button_frames), daemon=True)]
    for t in threads:
        t.start()
    try:
        td.run(pen_path, calib or dict(td.DEFAULT_CALIB))
    finally:
        td.find_hidraw, td.unlock = orig_find, orig_unlock
        td.make_uinput, td.make_keys_uinput = orig_make, orig_make_keys
        for t in threads:
            t.join(timeout=2)
        shutil.rmtree(tmp, ignore_errors=True)
    return pen_ui, keys_ui, unlocks


FAILURES = []


def check(name, cond, detail=""):
    print(f"{'PASS' if cond else 'FAIL'}  {name}{'  -- ' + detail if detail and not cond else ''}")
    if not cond:
        FAILURES.append(name)


def test_pen_maps_across_full_range():
    calib = dict(td.DEFAULT_CALIB)
    frames = [pen_report(calib["x_min"], 0, 0),
              pen_report(calib["x_max"], td.RAW_MAX, 8000, td.IN_RANGE_BIT | td.TIP_BIT)]
    pen, _, _ = drive(frames)
    xs = pen.values(e.EV_ABS, e.ABS_X)
    ys = pen.values(e.EV_ABS, e.ABS_Y)
    check("left edge of the pad maps to 0", xs and xs[0] == 0, f"got {xs}")
    check("right edge maps to the far side", xs and xs[-1] == td.OUT_MAX, f"got {xs}")
    check("Y uses its whole range", ys and ys[0] == 0 and ys[-1] == td.OUT_MAX, f"got {ys}")


def test_tip_drives_touch_and_pressure():
    frames = [pen_report(20000, 100, 29),  # hover: pressure above a light touch
              pen_report(20000, 100, 11, td.IN_RANGE_BIT | td.TIP_BIT)]
    pen, _, _ = drive(frames)
    touch = pen.values(e.EV_KEY, e.BTN_TOUCH)
    pressure = pen.values(e.EV_ABS, e.ABS_PRESSURE)
    check("hover reports no contact", touch and touch[0] == 0, f"got {touch}")
    check("tip switch reports contact", 1 in touch, f"got {touch}")
    check("hover pressure is zero despite raw 29", pressure and pressure[0] == 0, f"got {pressure}")
    # The last value is the release the proximity timeout emits, not the touch.
    check("light touch outranks hover", max(pressure) >= td.TIP_FLOOR, f"got {pressure}")


def test_pen_lift_is_announced():
    """The pad usually just goes quiet; the driver has to end the stroke itself."""
    frames = [pen_report(20000, 100, 9000, td.IN_RANGE_BIT | td.TIP_BIT)]
    pen, _, _ = drive(frames)
    touch = pen.values(e.EV_KEY, e.BTN_TOUCH)
    tool = pen.values(e.EV_KEY, e.BTN_TOOL_PEN)
    check("tip is released when the pad falls silent", touch and touch[-1] == 0, f"got {touch}")
    check("proximity ends too", tool and tool[-1] == 0, f"got {tool}")


def test_wrong_pen_mode_recovers():
    """Report id 6 means the handshake toggled one step too far."""
    frames = [other_mode_report() for _ in range(td.WRONG_MODE_LIMIT + 5)]
    frames += [pen_report(20000, 100, 0)]
    pen, _, unlocks = drive(frames)
    check("driver re-toggles the pen mode", len(unlocks) == 1, f"unlocked {len(unlocks)} times")
    check("and keeps working afterwards", pen.values(e.EV_ABS, e.ABS_X), "no position published")


def test_wrong_mode_does_not_toggle_forever():
    frames = [other_mode_report() for _ in range((td.MAX_RETOGGLES + 3) * td.WRONG_MODE_LIMIT)]
    _, _, unlocks = drive(frames)
    check("re-toggling is bounded", len(unlocks) <= td.MAX_RETOGGLES,
          f"unlocked {len(unlocks)} times, limit {td.MAX_RETOGGLES}")


def test_pen_buttons():
    buttons = [button_report(mask5=0x20), button_report(), button_report(mask5=0x10), button_report()]
    pen, _, _ = drive([pen_report(20000, 100, 0)], buttons)

    def transitions(code):
        # The proximity timeout releases the stylus buttons when the pad goes
        # quiet, so a leading 0 is expected and carries no information.
        seq = pen.values(e.EV_KEY, code)
        while seq and seq[0] == 0:
            seq.pop(0)
        return seq

    lower, upper = transitions(e.BTN_STYLUS), transitions(e.BTN_STYLUS2)
    check("lower pen button presses and releases", lower[:2] == [1, 0], f"got {lower}")
    check("upper pen button presses and releases", upper[:2] == [1, 0], f"got {upper}")


def test_express_keys():
    buttons = []
    for offset, bit in td.EXPRESS_KEY_BITS:
        buttons.append(button_report(**{f"mask{offset}": bit}))
        buttons.append(button_report())
    _, keys, _ = drive([pen_report(20000, 100, 0)], buttons)
    pressed = [c for t, c, v in keys.events if v == 1]
    expected = [getattr(e, n) for n in td.EXPRESS_KEY_NAMES]
    check("all 12 express keys are distinct", sorted(pressed) == sorted(expected),
          f"got {len(set(pressed))} distinct of {len(expected)}")
    for code in set(pressed):
        ups = len([1 for t, c, v in keys.events if c == code and v == 0])
        downs = len([1 for t, c, v in keys.events if c == code and v == 1])
        check(f"{e.KEY[code]} releases as often as it presses", ups == downs, f"{downs} down, {ups} up")


def test_no_key_sticks_when_several_are_held():
    buttons = [button_report(mask4=0x01), button_report(mask4=0x03), button_report(mask4=0x02),
               button_report()]
    _, keys, _ = drive([pen_report(20000, 100, 0)], buttons)
    held = set()
    for _, code, value in keys.events:
        held.add(code) if value else held.discard(code)
    check("nothing is left held down", not held, f"still down: {held}")


def main():
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            print(f"\n-- {name[5:].replace('_', ' ')}")
            fn()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} failure(s): {', '.join(FAILURES)}")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
