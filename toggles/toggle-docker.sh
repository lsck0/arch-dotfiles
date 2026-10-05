#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# docker.socket stays enabled either way (lazy-start on first `docker` command).
toggle_service docker "Docker" docker.service "${1:-toggle}"
