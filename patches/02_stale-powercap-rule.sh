#!/usr/bin/env bash
# drop 99-powercap.rules (generation 387, chmod a+r energy_uj): it sorts after 99-powercap-readable.rules and undoes its o-r

set -euo pipefail

RULE=/etc/udev/rules.d/99-powercap.rules

[[ -e "$RULE" ]] || exit 0
rm -f "$RULE"
udevadm control --reload-rules
udevadm trigger --action=add --subsystem-match=powercap
