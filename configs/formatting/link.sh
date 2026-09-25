#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1
set -ex
ln -sfn "${PWD}/clang-format"    "${HOME}/.clang-format"
ln -sfn "${PWD}/stylua.toml"     "${HOME}/.stylua.toml"
ln -sfn "${PWD}/prettierrc.json" "${HOME}/.prettierrc"
ln -sfn "${PWD}/editorconfig"    "${HOME}/.editorconfig"
ln -sfn "${PWD}/chktexrc"        "${HOME}/.chktexrc"

# latexindent finds its config through ~/.indentconfig.yaml, which lists paths
mkdir -p "${HOME}/.config/latexindent"
ln -sfn "${PWD}/latexindent.yaml" "${HOME}/.config/latexindent/latexindent.yaml"
printf 'paths:\n  - %s\n' "${HOME}/.config/latexindent/latexindent.yaml" > "${HOME}/.indentconfig.yaml"
