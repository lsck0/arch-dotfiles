#!/usr/bin/env bash

# needs the sched_ext kernel class and the scheduler binary; the wsl kernel has neither
if [[ ! -d /sys/kernel/sched_ext ]] || ! command -v scx_lavd >/dev/null 2>&1 || [[ "$FORM_FACTOR" == wsl ]]; then
    exit 0
fi

install -m755 scx.sh /usr/local/bin/scx-lavd-mode
unit_install scx-lavd.service
# starting can fail where sched_ext cannot attach (a vm), the next boot starts it
systemctl enable scx-lavd.service
systemctl start scx-lavd.service || true

# only a laptop changes power source, so only it needs the refresh timer and the ac-plug hook
if [[ "$FORM_FACTOR" == laptop ]]; then
    install -Dm644 49-scx-power.rules /etc/udev/rules.d/49-scx-power.rules
    udevadm control --reload-rules
    unit_install scx-mode.service scx-mode.timer
    systemctl enable scx-mode.timer
    systemctl start scx-mode.timer || true
fi
