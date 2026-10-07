#!/usr/bin/env bash

link_into "${HOME}/.config/pacman" makepkg.conf

# yay cache cleanup
unit_install yay-cache-clean.service yay-cache-clean.timer
systemctl --user enable --now yay-cache-clean.timer
