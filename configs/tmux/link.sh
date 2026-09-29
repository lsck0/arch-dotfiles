#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v git >/dev/null 2>&1 || ! command -v cargo >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p ${HOME}/.config/tmux

ln -sfn ${PWD}/tmux.conf ${HOME}/.config/tmux/tmux.conf

git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm || true

# Install the @plugin list so tpm sources each plugin's .tmux; it otherwise only
# clones on prefix+I, so a fresh machine never binds them (tmux-fingers `o` etc).
# The fingers binary itself comes from the tmux-fingers package, not this clone.
TMUX_PLUGIN_MANAGER_PATH="${HOME}/.tmux/plugins" \
    ~/.tmux/plugins/tpm/bin/install_plugins || true

~/.cargo/bin/tms config -p ${HOME}/projects
