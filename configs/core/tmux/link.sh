#!/usr/bin/env bash

link_into "${HOME}/.config/tmux" tmux.conf popup.sh

# tmux.conf runs the plugin's .tmux file directly; pinned here, no plugin manager
fetch_git_pinned https://github.com/b0o/tmux-autoreload e98aa3b74cfd5f2df2be2b5d4aa4ddcc843b2eba \
    "${HOME}/.config/tmux/plugins/tmux-autoreload"

tms config -p "${HOME}/projects"
