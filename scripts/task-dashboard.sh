#!/usr/bin/env bash
# task-dashboard — delegates to the maintained implementation in
# skills/l-agent-task-db/scripts/ (issue 20: one dashboard, not two).
set -euo pipefail

repo_root=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
exec python3 "$repo_root/skills/l-agent-task-db/scripts/task-dashboard.py" "$@"
