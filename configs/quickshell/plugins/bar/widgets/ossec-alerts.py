#!/usr/bin/env python3
"""OSSEC HIDS alert summary for the bar, one JSON line per poll, read by Ossec.qml.

The alert log is root-only, so it is read through `sudo -n` (this repo grants
passwordless sudo). Emits counts over a 24h window, the highest level seen, and
a few recent alerts for the tooltip. Prints {"ok": false, ...} on any failure,
which the widget renders as "unreadable" and dims itself.
"""

import json
import re
import subprocess
import sys
import time
from datetime import datetime

ALERTS = "/var/lib/ossec-hids/logs/alerts/alerts.log"
INTERVAL = int(sys.argv[1]) if len(sys.argv) > 1 else 60
WINDOW = 24 * 3600
HIGH = 7          # level >= HIGH is a problem worth turning the shield urgent
RECENT = 6

ALERT_RE = re.compile(r"^\*\* Alert (\d+)\.\d+:")
RULE_RE = re.compile(r"^Rule: (\d+) \(level (\d+)\) -> '(.*)'")


def read_log():
    try:
        done = subprocess.run(["sudo", "-n", "cat", ALERTS],
                              capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None
    return done.stdout if done.returncode == 0 else None


def parse(text, now):
    alerts = []
    for chunk in text.split("** Alert ")[1:]:
        block = "** Alert " + chunk
        m = ALERT_RE.match(block)
        if not m:
            continue
        ts = int(m.group(1))
        if now - ts > WINDOW:
            continue
        level, rule, desc = 0, "", ""
        for line in block.splitlines():
            rm = RULE_RE.match(line)
            if rm:
                rule, level, desc = rm.group(1), int(rm.group(2)), rm.group(3)
                break
        alerts.append({"ts": ts, "level": level, "rule": rule, "desc": desc})
    alerts.sort(key=lambda a: a["ts"], reverse=True)
    return alerts


def emit(now):
    text = read_log()
    if text is None:
        print(json.dumps({"ok": False, "error": "read"}))
        return
    a = parse(text, now)
    print(json.dumps({
        "ok": True,
        "total": len(a),
        "high": sum(1 for x in a if x["level"] >= HIGH),
        "maxLevel": max((x["level"] for x in a), default=0),
        "recent": [{
            "t": datetime.fromtimestamp(x["ts"]).strftime("%H:%M"),
            "level": x["level"], "rule": x["rule"], "desc": x["desc"],
        } for x in a[:RECENT]],
    }))


def main():
    while True:
        try:
            emit(int(time.time()))
        except Exception:
            print(json.dumps({"ok": False, "error": "exc"}))
        sys.stdout.flush()
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
