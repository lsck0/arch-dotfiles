#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
exec "$repo_root/skills/l-agent-task-db/scripts/scaffold.sh" "${1:-$PWD}"
