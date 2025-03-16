#!/bin/env bash

set -ex

mkdir -p ${HOME}/.config/tmux
ln -sf ${PWD}/tmux.conf ${HOME}/.config/tmux/tmux.conf
