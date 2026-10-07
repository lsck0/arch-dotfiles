#!/usr/bin/env bash

# login shell is set at user creation (bootstrap, adduser-dotfiles), not here
mkdir -p "${HOME}/.zsh/completions"
ln -sfn "${PWD}/zshrc" "${HOME}/.zshrc"
