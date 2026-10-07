#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1
set -e
# clang-format, stylua, prettier, rustfmt and ruff configs reach only projects without their own, via nvim conform
ln -sfn "${PWD}/chktexrc" "${HOME}/.chktexrc"

# latexindent finds its config via ~/.indentconfig.yaml
mkdir -p "${HOME}/.config/latexindent"
ln -sfn "${PWD}/latexindent.yaml" "${HOME}/.config/latexindent/latexindent.yaml"
printf 'paths:\n  - %s\n' "${HOME}/.config/latexindent/latexindent.yaml" > "${HOME}/.indentconfig.yaml"
