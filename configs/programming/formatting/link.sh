#!/usr/bin/env bash
# clang-format, stylua, prettier, rustfmt and ruff configs are never linked: nvim conform and emacs apheleia pass them
# only to projects without their own
link_as "${PWD}/chktexrc" "${HOME}/.chktexrc"

# latexindent finds its config via ~/.indentconfig.yaml
link_into "${HOME}/.config/latexindent" latexindent.yaml
# through file_update: an ~/.indentconfig.yaml of a person's own is kept aside, never overwritten
tmp=$(mktemp)
printf 'paths:\n  - %s\n' "${HOME}/.config/latexindent/latexindent.yaml" >"$tmp"
file_update "$tmp" "${HOME}/.indentconfig.yaml" || true
rm -f "$tmp"
