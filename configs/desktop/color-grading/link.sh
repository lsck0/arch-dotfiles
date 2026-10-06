#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

# wlr-gamma-control is a wlroots/hyprland protocol

set -e

chmod 755 "${PWD}/color-grading.py"
mkdir -p "${HOME}/.config/systemd/user"
ln -sfn "${PWD}/color-grading.service" "${HOME}/.config/systemd/user/color-grading.service"
systemctl --user daemon-reload
systemctl --user enable color-grading.service
# outside a session (fresh install from a tty) the next login starts it
if systemctl --user is-active -q graphical-session.target; then
    systemctl --user restart color-grading.service
fi
