#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source ../../scripts/lib/platform.sh
ff=$(platform_form_factor ../..)
# needs the sched_ext kernel class and the scheduler binary; the wsl kernel has neither
if [[ ! -d /sys/kernel/sched_ext ]] || ! command -v scx_lavd >/dev/null 2>&1 || [[ "$ff" == wsl ]]; then
    exit 0
fi

set -e

sudo install -m755 scx.sh /usr/local/bin/scx-lavd-mode
sudo install -m644 scx-lavd.service /etc/systemd/system/scx-lavd.service

# only a laptop changes power source, so only it needs the refresh timer and the ac-plug hook
if [[ "$ff" == laptop ]]; then
    sudo install -m644 scx-mode.service /etc/systemd/system/scx-mode.service
    sudo install -m644 scx-mode.timer /etc/systemd/system/scx-mode.timer
    sudo install -m644 49-scx-power.rules /etc/udev/rules.d/49-scx-power.rules
    sudo udevadm control --reload-rules
fi

sudo systemctl daemon-reload
sudo systemctl enable --now scx-lavd.service
[[ "$ff" == laptop ]] && sudo systemctl enable --now scx-mode.timer
