#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

toggle_service oom-protection "OOM Protection" systemd-oomd.service "${1:-toggle}"
