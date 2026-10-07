#!/usr/bin/env bash
# wlr-gamma-control is a wlroots/hyprland protocol

unit_install color-grading.service
systemctl --user enable color-grading.service
# outside a session (fresh install from a tty) the next login starts it
if systemctl --user is-active -q graphical-session.target; then
    systemctl --user restart color-grading.service
fi
