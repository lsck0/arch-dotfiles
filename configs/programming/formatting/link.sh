#!/usr/bin/env bash
# clang-format, stylua, prettier, rustfmt and ruff configs are never linked: nvim conform and emacs apheleia pass them
# only to projects without their own
ln -sfn "${PWD}/chktexrc" "${HOME}/.chktexrc"

# latexindent finds its config via ~/.indentconfig.yaml
link_into "${HOME}/.config/latexindent" latexindent.yaml
printf 'paths:\n  - %s\n' "${HOME}/.config/latexindent/latexindent.yaml" > "${HOME}/.indentconfig.yaml"
