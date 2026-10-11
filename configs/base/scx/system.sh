#!/usr/bin/env bash

# laptop only: scx_lavd's core compaction and frequency control save power, but it ignores cgroup cpu.weight (no
# cgroup_set_weight; bpfland neither, flash only a task's leaf cgroup), so the desktop keeps eevdf, where session.slice
# (base/oomd) outweighs a build hierarchically; nice still applies under both
if [[ "$FORM_FACTOR" != laptop || ! -d /sys/kernel/sched_ext ]] || ! command -v scx_lavd >/dev/null 2>&1; then
    if [[ -e /etc/systemd/system/scx-lavd.service ]]; then
        systemctl disable --now scx-lavd.service 2>/dev/null || true
        rm -f /etc/systemd/system/scx-lavd.service
        systemctl daemon-reload
    fi
    exit 0
fi

if file_update scx-lavd.service /etc/systemd/system/scx-lavd.service; then
    systemctl daemon-reload
    action=restart
else
    action=start
fi
systemctl enable scx-lavd.service
# a failed attach falls back to eevdf, the next boot retries
systemctl "$action" scx-lavd.service || true
