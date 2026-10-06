#!/usr/bin/env bash

set -euo pipefail

command -v ss >/dev/null 2>&1 || exit 0

ss -Htn state established '( sport = :2222 )' 2>/dev/null | grep -q . && exit 1
exit 0
