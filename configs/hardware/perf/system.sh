#!/usr/bin/env bash
# I/O scheduler tuning (all machines) + a CPU governor policy per form-factor.
[[ "$FORM_FACTOR" != wsl ]] || exit 0

install -Dm644 60-ioschedulers.rules /etc/udev/rules.d/60-ioschedulers.rules
udevadm control --reload 2>/dev/null || true
udevadm trigger --subsystem-match=block 2>/dev/null || true

# desktops: schedutil (balanced, scales with load); laptops are left to tlp's dynamic policy; vm/other: leave default
case "$FORM_FACTOR" in
    desktop)
        file_render cpu-governor.service /etc/systemd/system/cpu-governor.service GOVERNOR=schedutil
        systemctl daemon-reload
        systemctl enable --now cpu-governor.service
        ;;
    *)
        systemctl disable --now cpu-governor.service 2>/dev/null || true
        rm -f /etc/systemd/system/cpu-governor.service
        systemctl daemon-reload 2>/dev/null || true
        ;;
esac
