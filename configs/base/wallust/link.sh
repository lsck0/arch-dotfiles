#!/usr/bin/env bash

link_into "${HOME}/.config/wallust" templates wallust.toml
shopt -s nullglob
link_into "${HOME}/.config/wallust/colorschemes" ../themes/*.json
