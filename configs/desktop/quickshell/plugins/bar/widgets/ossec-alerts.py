#!/usr/bin/env python3
"""OSSEC alert summary for System.qml: one JSON line per change, inotify driven, silent exit when ossec is off.

The log is root-only by package default; configs/hardware/ossec grants the ossec-alerts group read access via ACL.
"""

import ctypes
import json
import os
import select
import subprocess
import time
from collections import deque
from datetime import datetime

ALERTS_DIR = "/var/lib/ossec-hids/logs/alerts"
ALERTS_LOG = ALERTS_DIR + "/alerts.log"
OSSEC_TARGET = "ossec-server.target"
WINDOW_S = 24 * 3600
# ossec levels: 7 fires on every syscheck change after an upgrade, 10+ is repeated failures or high importance
LEVEL_HIGH = 10
RECENT_COUNT = 6
# a syscheck scan writes alerts in bursts, one summary per burst
DEBOUNCE_S = 0.5
ALERT_MARK = "** Alert "
RULE_MARK = "Rule: "
IN_MODIFY = 0x002
IN_MOVED_TO = 0x080
IN_CREATE = 0x100
EVENTS_SIZE_BYTES = 4096


def ossec_is_active():
    done = subprocess.run(["systemctl", "is-active", "--quiet", OSSEC_TARGET], check=False)
    return done.returncode == 0


def alerts_watch_create():
    libc = ctypes.CDLL(None, use_errno=True)
    fd = libc.inotify_init1(os.O_CLOEXEC)
    if fd < 0:
        return None
    if libc.inotify_add_watch(fd, ALERTS_DIR.encode(), IN_MODIFY | IN_MOVED_TO | IN_CREATE) < 0:
        os.close(fd)
        return None
    return fd


# block format: "** Alert <ts>.<id>: ..." then a date line, then "Rule: <id> (level <n>) -> '<desc>'"
def alert_parse(block):
    head, _, rest = block.partition("\n")
    ts = head[len(ALERT_MARK):].split(".", 1)[0]
    if not ts.isdigit():
        return None
    for line in rest.splitlines():
        if not line.startswith(RULE_MARK):
            continue
        rule, _, tail = line[len(RULE_MARK):].partition(" (level ")
        level, _, desc = tail.partition(") -> ")
        if not level.isdigit():
            return None
        return (int(ts), int(level), rule, desc.strip("'"))
    return None


class Tail:
    inode = 0
    offset = 0
    pending = ""


# only whole alerts, ossec terminates each with a blank line
def tail_read_alerts(tail):
    try:
        st = os.stat(ALERTS_LOG)
    except OSError:
        return []
    if st.st_ino != tail.inode or st.st_size < tail.offset:
        tail.inode, tail.offset, tail.pending = st.st_ino, 0, ""
    with open(ALERTS_LOG, "rb") as f:
        f.seek(tail.offset)
        data = f.read()
    tail.offset += len(data)
    text = tail.pending + data.decode(errors="replace")
    cut = text.rfind("\n\n") + 2
    text, tail.pending = text[:cut], text[cut:]
    blocks = (ALERT_MARK + chunk for chunk in text.split(ALERT_MARK)[1:])
    return [a for a in map(alert_parse, blocks) if a]


def summary_to_json(alerts):
    recent = list(alerts)[-RECENT_COUNT:][::-1]
    return json.dumps({
        "total": len(alerts),
        "high": sum(1 for a in alerts if a[1] >= LEVEL_HIGH),
        "maxLevel": max((a[1] for a in alerts), default=0),
        "recent": [{"t": datetime.fromtimestamp(ts).strftime("%H:%M"), "level": level, "rule": rule, "desc": desc}
                   for ts, level, rule, desc in recent],
    })


def main():
    if not ossec_is_active():
        return
    fd = alerts_watch_create()
    if fd is None:
        return
    tail, alerts, last = Tail(), deque(), ""
    while True:
        alerts.extend(tail_read_alerts(tail))
        now = time.time()
        while alerts and alerts[0][0] < now - WINDOW_S:
            alerts.popleft()
        line = summary_to_json(alerts)
        if line != last:
            print(line, flush=True)
            last = line
        # wake on the next write or when the oldest alert leaves the window, never on a fixed tick
        expiry_s = alerts[0][0] + WINDOW_S - now + 1 if alerts else None
        if select.select([fd], [], [], expiry_s)[0]:
            time.sleep(DEBOUNCE_S)
            os.read(fd, EVENTS_SIZE_BYTES)


if __name__ == "__main__":
    main()
