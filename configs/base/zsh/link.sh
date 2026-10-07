#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

mkdir -p ~/.zsh/completions

ln -sfn "${PWD}/zshrc" "${HOME}/.zshrc"

[[ "$(getent passwd "$USER" | cut -d: -f7)" == /usr/bin/zsh ]] || sudo chsh -s /usr/bin/zsh "$USER"
