#!/usr/bin/env bash

link_into "$HOME/.config/sioyek" prefs_user.config keys_user.config
# command on PATH, invoked bare by tmux/herdr/nvim/viewers
link_commands synctex-edit.sh
