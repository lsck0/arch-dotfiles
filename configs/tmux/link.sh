#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v git >/dev/null 2>&1 || ! command -v cargo >/dev/null 2>&1; then
    exit 0
fi

set -e

mkdir -p "${HOME}/.config/tmux"

ln -sfn "${PWD}/tmux.conf" "${HOME}/.config/tmux/tmux.conf"

git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm || true

# tpm otherwise only installs plugins on prefix+I
TMUX_PLUGIN_MANAGER_PATH="${HOME}/.tmux/plugins" \
    ~/.tmux/plugins/tpm/bin/install_plugins || true

# tms comes from cargo or pacman; skip its config when neither installed it
if command -v tms >/dev/null 2>&1; then
    tms config -p "${HOME}/projects"
fi
