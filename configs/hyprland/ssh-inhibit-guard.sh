#!/usr/bin/env bash

set -euo pipefail

command -v ss >/dev/null 2>&1 || exit 0

ss -tn state established '( sport = :22 )' 2>/dev/null | grep -q . && exit 1
exit 0
