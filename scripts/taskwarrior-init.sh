#!/usr/bin/env bash
# Scaffold an agent task db in a project dir (wraps l-agent-task-db/scaffold.sh).

set -euo pipefail

repo_root=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
exec "$repo_root/skills/l-agent-task-db/scripts/scaffold.sh" "${1:-$PWD}"
