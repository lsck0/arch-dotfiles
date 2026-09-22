#!/usr/bin/env python3
"""Claude Code usage for the bar, in the shape the TRMNL plugin renders.

This used to sum today's tokens out of ~/.claude/projects itself and say so in
a tooltip, because the plan-limit percentages live behind an endpoint this repo
had no client for. configs/trmnl-claude vendors one now, so the widget shows
the same numbers as the e-ink display rather than a weaker local subset.

claude_trmnl.py --dry-run builds its payload and prints it instead of posting,
which is exactly what is wanted here: no webhook UUID, no push to the display,
no fleet store written. --usage-method headers bounds the call at one
max_tokens:1 request; "auto" would fall back to driving the /usage TUI through
a PTY, which takes about twenty seconds and is no way to feed a bar.

Prints {} when the script is missing or fails, which the widget reads as
"nothing to show" and hides itself.
"""

import json
import pathlib
import subprocess
import sys

# configs/quickshell/plugins/bar/widgets -> configs/trmnl-claude
SCRIPT = pathlib.Path(__file__).resolve().parents[4] / "trmnl-claude" / "claude_trmnl.py"
TIMEOUT = 60


def main():
    if not SCRIPT.exists():
        print("{}")
        return 0
    try:
        done = subprocess.run(
            [sys.executable, str(SCRIPT), "--dry-run", "--usage-method", "headers"],
            capture_output=True, text=True, timeout=TIMEOUT)
    except (OSError, subprocess.SubprocessError):
        print("{}")
        return 0
    if done.returncode != 0:
        print("{}")
        return 0
    try:
        payload = json.loads(done.stdout)
    except ValueError:
        print("{}")
        return 0
    print(json.dumps(payload))
    return 0


if __name__ == "__main__":
    sys.exit(main())
