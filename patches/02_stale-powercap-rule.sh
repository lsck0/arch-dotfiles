#!/usr/bin/env bash
# drop 99-powercap.rules (generation 387, chmod a+r energy_uj): it sorts after 99-powercap-readable.rules and undoes its o-r

set -euo pipefail

RULE=/etc/udev/rules.d/99-powercap.rules

[[ -e "$RULE" ]] || exit 0
sudo rm -f "$RULE"
sudo udevadm control --reload-rules
sudo udevadm trigger --action=add --subsystem-match=powercap
