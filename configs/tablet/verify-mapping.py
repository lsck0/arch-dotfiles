#!/usr/bin/env python3
"""Check where the graphics tablet actually puts the cursor.

Reads raw pen coordinates straight off the evdev node and samples Hyprland's
cursor position at the same time, then reconstructs the transfer function
from tablet position to screen position.

This deliberately does more than compare the extremes: a mapping that is
clamped, folded or offset can still reach both edges of the screen, so only
the shape of the curve tells you whether the mapping is really bijective.

Usage: verify-mapping.py [seconds] [monitor]
Sweep the pen over the whole tablet, corner to corner, while it runs.
"""

import fcntl
import glob
import json
import os
import re
import select
import socket
import struct
import sys
import time

EV_FMT = "llHHi"
EV_SIZE = struct.calcsize(EV_FMT)
EV_ABS, ABS_X, ABS_Y = 3, 0, 1
EVIOCGNAME = 0x81004506
BINS = 16


def ioctl_name(fd):
    buf = bytearray(256)
    fcntl.ioctl(fd, EVIOCGNAME, buf)
    return buf.split(b"\0")[0].decode()


def abs_range(fd, axis):
    buf = bytearray(24)
    fcntl.ioctl(fd, 0x80184540 + axis, buf)
    _, mn, mx, _, _, res = struct.unpack("iiiiii", buf)
    return mn, mx, res


def find_pen():
    """The pen is the evdev node with X/Y and a plausible physical size."""
    override = os.environ.get("TABLET_NODE")
    candidates = [override] if override else sorted(glob.glob("/dev/input/event*"))
    for path in candidates:
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        except OSError:
            continue
        try:
            xmin, xmax, xres = abs_range(fd, ABS_X)
            ymin, ymax, yres = abs_range(fd, ABS_Y)
        except OSError:
            os.close(fd)
            continue
        if xmax <= xmin or ymax <= ymin or not xres or not yres:
            os.close(fd)
            continue
        width, height = (xmax - xmin) / xres, (ymax - ymin) / yres
        if not (80 <= width <= 600 and 50 <= height <= 400):
            os.close(fd)
            continue
        return path, fd, ioctl_name(fd), (xmin, xmax), (ymin, ymax), width, height
    return None


def hypr_socket():
    runtime = os.environ.get("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid())
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not sig:
        cands = [c for c in sorted(glob.glob(os.path.join(runtime, "hypr", "*"))) if os.path.isdir(c)]
        if not cands:
            return None
        sig = os.path.basename(cands[-1])
    return os.path.join(runtime, "hypr", sig, ".socket.sock")


def hypr(sock_path, command):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sock_path)
    s.sendall(command.encode())
    out = b""
    while True:
        chunk = s.recv(8192)
        if not chunk:
            break
        out += chunk
    s.close()
    return out.decode()


def summarise(axis, raw_lo, raw_hi, scr_lo, scr_hi, pairs):
    """Bin raw positions and report the screen position reached in each bin."""
    buckets = [[] for _ in range(BINS)]
    for raw, scr in pairs:
        idx = int((raw - raw_lo) / max(raw_hi - raw_lo, 1) * BINS)
        buckets[min(max(idx, 0), BINS - 1)].append(scr)

    print(f"\n{axis}: tablet position -> screen position")
    print(f"  {'tablet':>12}   {'screen':>9}   {'expected':>9}   graph")
    filled = 0
    flat = 0
    worst = 0.0
    prev = None
    for i, vals in enumerate(buckets):
        lo = raw_lo + (raw_hi - raw_lo) * i / BINS
        hi = raw_lo + (raw_hi - raw_lo) * (i + 1) / BINS
        label = f"{lo / raw_hi:4.0%}-{hi / raw_hi:4.0%}"
        if not vals:
            print(f"  {label:>12}   {'(not swept)':>21}")
            continue
        filled += 1
        mid = (lo + hi) / 2
        want = scr_lo + (scr_hi - scr_lo) * (mid - raw_lo) / (raw_hi - raw_lo)
        got = sum(vals) / len(vals)
        worst = max(worst, abs(got - want) / (scr_hi - scr_lo))
        if prev is not None and abs(got - prev) < (scr_hi - scr_lo) * 0.01:
            flat += 1
        prev = got
        pos = int((got - scr_lo) / (scr_hi - scr_lo) * 40)
        bar = " " * max(min(pos, 40), 0) + "#"
        print(f"  {label:>12}   {got:>9.0f}   {want:>9.0f}   {bar}")

    if filled < BINS * 0.7:
        print(f"  -> only {filled}/{BINS} of the tablet was swept, inconclusive")
        return None
    print(f"  -> worst deviation from a straight line: {worst:.1%} of the screen")
    if flat:
        print(f"  -> {flat} neighbouring bands gave the same screen position (clamped)")
    return worst < 0.05 and flat == 0


def main():
    seconds = float(sys.argv[1]) if len(sys.argv) > 1 else 30.0
    want = sys.argv[2] if len(sys.argv) > 2 else None

    pen = find_pen()
    if not pen:
        sys.exit("no readable pen device found (is the tablet plugged in?)")
    path, fd, name, (xmin, xmax), (ymin, ymax), width_mm, height_mm = pen
    print(f"pen      : {name}")
    print(f"node     : {path}")
    print(f"raw range: x {xmin}..{xmax}  y {ymin}..{ymax}   area {width_mm:.0f} x {height_mm:.0f} mm")

    sock = hypr_socket()
    if not sock or not os.path.exists(sock):
        sys.exit("cannot reach the Hyprland socket")

    monitors = json.loads(hypr(sock, "j/monitors"))
    for m in monitors:
        m["rect"] = (m["x"], m["y"], m["x"] + m["width"] / m["scale"], m["y"] + m["height"] / m["scale"])
    if want is None:
        want = max(monitors, key=lambda m: m["x"])["name"]
    target = next((m for m in monitors if m["name"] == want), None)
    if target is None:
        sys.exit(f"no monitor named {want}")
    tx0, ty0, tx1, ty1 = target["rect"]
    print(f"target   : {want}  logical {tx0:.0f},{ty0:.0f} .. {tx1:.0f},{ty1:.0f}")
    print(f"\nsweep the whole tablet, corner to corner, for {seconds:.0f}s ...")

    px = py = None
    xs, ys, offscreen = [], [], 0
    end = time.time() + seconds
    last = 0.0
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.02)
        if r:
            data = os.read(fd, EV_SIZE * 64)
            for i in range(0, len(data) - EV_SIZE + 1, EV_SIZE):
                _, _, typ, code, val = struct.unpack(EV_FMT, data[i : i + EV_SIZE])
                if typ == EV_ABS and code == ABS_X:
                    px = val
                elif typ == EV_ABS and code == ABS_Y:
                    py = val
        now = time.time()
        if px is not None and py is not None and now - last > 0.03:
            last = now
            m = re.search(r"(-?\d+)\D+(-?\d+)", hypr(sock, "cursorpos"))
            if not m:
                continue
            cx, cy = int(m.group(1)), int(m.group(2))
            xs.append((px, cx))
            ys.append((py, cy))
            if not (tx0 - 1 <= cx <= tx1 and ty0 - 1 <= cy <= ty1):
                offscreen += 1

    os.close(fd)

    if len(xs) < 50:
        sys.exit(f"\nonly {len(xs)} samples - was the pen moved on the tablet?")
    print(f"samples  : {len(xs)}")

    okx = summarise("horizontal", xmin, xmax, tx0, tx1, xs)
    oky = summarise("vertical", ymin, ymax, ty0, ty1, ys)

    print()
    if offscreen:
        print(f"FAIL: {offscreen}/{len(xs)} samples landed outside {want}")
    else:
        print(f"OK  : every sample stayed on {want}")
    if okx and oky and not offscreen:
        print("OK  : the mapping is bijective across the whole tablet")
        sys.exit(0)
    if okx is None or oky is None:
        sys.exit(2)
    print("FAIL: the mapping is not a straight bijective map onto the monitor")
    sys.exit(1)


if __name__ == "__main__":
    main()
