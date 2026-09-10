#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# docker.socket stays enabled either way (lazy-start on first `docker` command).
# This just forces dockerd to actually be running persistently, e.g. before a
# long-running compose stack, instead of only spinning up on demand.
check() { systemctl is-active --quiet docker.service && echo on || echo off; }
turn_on() { sudo systemctl start docker.service; }
turn_off() { sudo systemctl stop docker.service; }

toggle_main docker "Docker" check turn_on turn_off "${1:-toggle}"
