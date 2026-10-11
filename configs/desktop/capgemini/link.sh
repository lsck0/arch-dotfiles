#!/usr/bin/env bash

profile_has work || exit 0

link_commands capgemini.sh
# a per-user copy: Exec needs the absolute path, ~/.local/bin is not on every session's PATH
file_render capgemini.desktop "${XDG_DATA_HOME:-$HOME/.local/share}/applications/capgemini.desktop" HOME="$HOME"
