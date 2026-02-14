#!/usr/bin/env bash

set -ex

yes | hyprpm update -f

yes | hyprpm add https://github.com/hyprwm/hyprland-plugins
yes | hyprpm add https://github.com/0xFMD/hyprmodoro
yes | hyprpm add https://github.com/virtcode/hypr-dynamic-cursors

hyprpm enable dynamic-cursors
hyprpm enable hyprexpo
hyprpm enable hyprscrolling
