#!/usr/bin/env bash
# Initialise the isolated taskwarrior/timewarrior database for a project.
# The canonical implementation lives with l-agent-task-db so the skill and
# the command cannot drift apart.
set -euo pipefail

repo_root=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
exec "$repo_root/skills/l-agent-task-db/scripts/scaffold.sh" "${1:-$PWD}"
