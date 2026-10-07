#!/usr/bin/env bash

link_into "${HOME}/.config/herdr" config.toml
# command on PATH, invoked bare by tmux/herdr/nvim/viewers
link_commands herdr-open.sh
