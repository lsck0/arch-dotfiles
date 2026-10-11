#!/usr/bin/env bash

link_into "${HOME}/.config/wallust" wallust.toml
link_dir "${PWD}/templates" "${HOME}/.config/wallust/templates"
shopt -s nullglob
link_into "${HOME}/.config/wallust/colorschemes" ../themes/*.json
