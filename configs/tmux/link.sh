#!/usr/bin/env bash

set -ex

mkdir -p ${HOME}/.config/tmux
ln -sf ${PWD}/tmux.conf ${HOME}/.config/tmux/tmux.conf

git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

~/.cargo/bin/tms config -p ${HOME}/code
