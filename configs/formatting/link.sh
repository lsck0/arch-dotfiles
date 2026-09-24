#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1
set -ex
ln -sfn "${PWD}/clang-format"    "${HOME}/.clang-format"
ln -sfn "${PWD}/stylua.toml"     "${HOME}/.stylua.toml"
ln -sfn "${PWD}/prettierrc.json" "${HOME}/.prettierrc"
ln -sfn "${PWD}/editorconfig"    "${HOME}/.editorconfig"
