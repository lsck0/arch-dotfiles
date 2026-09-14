#!/usr/bin/env bash

if ! command -v zsh >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p ~/.zsh/completions

ln -sfn ${PWD}/zshrc ${HOME}/.zshrc
