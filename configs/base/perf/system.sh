#!/usr/bin/env bash
# I/O scheduler tuning (all machines); the cpu side is tlp's epp (base/tlp), amd-pstate-epp's active mode offers no
# governor beyond performance and powersave
[[ "$FORM_FACTOR" != wsl ]] || exit 0

install -Dm644 60-ioschedulers.rules /etc/udev/rules.d/60-ioschedulers.rules
udevadm control --reload 2>/dev/null || true
udevadm trigger --subsystem-match=block 2>/dev/null || true
