#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1
set -e
ln -sfn "${PWD}/clang-format"    "${HOME}/.clang-format"
ln -sfn "${PWD}/stylua.toml"     "${HOME}/.stylua.toml"
ln -sfn "${PWD}/prettierrc.json" "${HOME}/.prettierrc"
ln -sfn "${PWD}/editorconfig"    "${HOME}/.editorconfig"
ln -sfn "${PWD}/chktexrc"        "${HOME}/.chktexrc"
ln -sfn "${PWD}/rustfmt.toml"    "${HOME}/.rustfmt.toml"
mkdir -p "${HOME}/.config/ruff"
ln -sfn "${PWD}/ruff.toml"       "${HOME}/.config/ruff/ruff.toml"

# latexindent finds its config via ~/.indentconfig.yaml
mkdir -p "${HOME}/.config/latexindent"
ln -sfn "${PWD}/latexindent.yaml" "${HOME}/.config/latexindent/latexindent.yaml"
printf 'paths:\n  - %s\n' "${HOME}/.config/latexindent/latexindent.yaml" > "${HOME}/.indentconfig.yaml"
