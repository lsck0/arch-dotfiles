#!/usr/bin/env bash

set -ex

mkdir -p ~/.zsh/completions

ln -sf ${PWD}/zshrc ${HOME}/.zshrc
