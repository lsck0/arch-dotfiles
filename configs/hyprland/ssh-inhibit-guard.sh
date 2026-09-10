#!/usr/bin/env bash
# hypridle condition_cmd for the suspend listener in hypridle.conf.
# Exit 0 = proceed with on-timeout (suspend), exit 1 = defer/retry.
# An active SSH session (someone connected in, doing real work) should never
# get cut off by an idle-triggered suspend just because there's no local
# keyboard/mouse activity. Locking is fine while sshed in — only suspend is
# guarded here.
set -euo pipefail

command -v ss >/dev/null 2>&1 || exit 0

ss -tn state established '( sport = :22 )' 2>/dev/null | grep -q . && exit 1
exit 0
