#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

mkdir -p "${HOME}/.config/gtk-3.0"

# overlays the oomox theme, survives palette regen
ln -sfn "${PWD}/gtk.css" "${HOME}/.config/gtk-3.0/gtk.css"
