#!/usr/bin/env bash
# drop 50-gparted-nopasswd.rules: gparted ran as root without a password, now pkexec asks
set -euo pipefail

RULE=/etc/polkit-1/rules.d/50-gparted-nopasswd.rules

[[ -e "$RULE" ]] || exit 0
rm -f "$RULE"
