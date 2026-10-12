#!/usr/bin/env bash

link_into "${HOME}/.config" gamemode.ini
# stable path for the [custom] hook so a checkout anywhere works (readlink -f in hook.sh resolves the real dir)
link_as "${PWD}/hook.sh" "${HOME}/.local/bin/gamemode-hook"
