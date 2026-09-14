#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
exec python3 "$repo_root/skills/l-agent-task-db/scripts/task-dashboard.py" "$@"
