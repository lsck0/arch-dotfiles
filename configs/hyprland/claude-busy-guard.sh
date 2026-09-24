#!/usr/bin/env bash
# hypridle condition_cmd: exit 1 (block suspend) while any claude session is actively working.

set -euo pipefail

dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/claude-busy"

# A marker is touched once at a turn's start and removed at its end.
find "$dir" -maxdepth 1 -type f -mmin +120 -delete 2>/dev/null || true

# block suspend if any session is still busy
find "$dir" -maxdepth 1 -type f -mmin -120 2>/dev/null | grep -q . && exit 1
exit 0
