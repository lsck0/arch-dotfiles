#!/usr/bin/env bash

link_into "${HOME}/.config/yazi" yazi.toml keymap.toml
# theme.toml is rendered by wallust
ln -sfn "${HOME}/.cache/wal/colors-yazi.toml" "${HOME}/.config/yazi/theme.toml"
