#!/usr/bin/env bash

set -ex

yes | hyprpm update -f

yes | hyprpm add https://github.com/hyprnux/hyprglass
yes | hyprpm add https://github.com/hyprwm/hyprland-plugins
yes | hyprpm add https://github.com/outfoxxed/hy3
yes | hyprpm add https://github.com/virtcode/hypr-dynamic-cursors

hyprpm enable dynamic-cursors
hyprpm enable Hyprspace
