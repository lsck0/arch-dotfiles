#!/usr/bin/env bash

# toolbox rewrites ~/.config/autostart/jetbrains-toolbox.desktop on every start, so mask the unit
# systemd-xdg-autostart-generator makes from it instead; the mask holds before toolbox ever ran
systemctl --user mask 'app-jetbrains\x2dtoolbox@autostart.service'
