#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v git >/dev/null 2>&1 || ! command -v cargo >/dev/null 2>&1; then
    exit 0
fi

set -e

mkdir -p "${HOME}/.config/tmux"

ln -sfn "${PWD}/tmux.conf" "${HOME}/.config/tmux/tmux.conf"

# tpm loads every @plugin of tmux.conf from the xdg plugin dir; pinned here, not by tpm's own clone of each head
source ../../../scripts/lib/fetch.sh
plugins="${HOME}/.config/tmux/plugins"
fetch_git_pinned https://github.com/tmux-plugins/tpm e261deb1b47614eed3400089ce7197dc68acc4eb "${plugins}/tpm"
fetch_git_pinned https://github.com/b0o/tmux-autoreload e98aa3b74cfd5f2df2be2b5d4aa4ddcc843b2eba "${plugins}/tmux-autoreload"
fetch_git_pinned https://github.com/Morantron/tmux-fingers fc3c750b8d73ac3e29675aae3b3ac6a00a0718f1 "${plugins}/tmux-fingers"

# tms comes from cargo or pacman; skip its config when neither installed it
if command -v tms >/dev/null 2>&1; then
    tms config -p "${HOME}/projects"
fi
