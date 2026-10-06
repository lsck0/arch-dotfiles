#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

mkdir -p ~/.zsh/completions

ln -sfn "${PWD}/zshrc" "${HOME}/.zshrc"
