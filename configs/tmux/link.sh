#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v git >/dev/null 2>&1 || ! command -v cargo >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p ${HOME}/.config/tmux

ln -sfn ${PWD}/tmux.conf ${HOME}/.config/tmux/tmux.conf

git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

~/.cargo/bin/tms config -p ${HOME}/projects
