#!/usr/bin/env python3
"""Claude Code usage for the bar via claude_trmnl.py --dry-run.

Prints the payload, {} when the widget does not apply (guest, no script), or {"error": why}
so the bar can say it failed instead of hiding.
"""

import getpass
import json
import pathlib
import subprocess
import sys

SCRIPT = pathlib.Path(__file__).resolve().parents[4] / "trmnl-claude" / "claude_trmnl.py"
TIMEOUT = 60


def fail(why):
    print(json.dumps({"error": why}))
    return 0


def main():
    # the claude usage widget is luca's; a guest gets nothing
    if getpass.getuser() != "luca" or not SCRIPT.exists():
        print("{}")
        return 0
    try:
        done = subprocess.run(
            # headers is one request, auto drives a slow pty
            [sys.executable, str(SCRIPT), "--dry-run", "--usage-method", "headers"],
            capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return fail("timeout")
    except (OSError, subprocess.SubprocessError):
        return fail("spawn")
    if done.returncode != 0:
        return fail("exit %d" % done.returncode)
    try:
        payload = json.loads(done.stdout)
    except ValueError:
        return fail("bad json")
    print(json.dumps(payload))
    return 0


if __name__ == "__main__":
    sys.exit(main())
