#!/usr/bin/env bash

set -e

SELECTED=$(shimejictl list | sed '1d; s/^[0-9]\+: //' | paste -sd '\n' - | "$(dirname "$(readlink -f "$0")")/picker.sh" -p "Shimeji")

if [[ "$SELECTED" == "CNCLD" || -z "$SELECTED" ]]; then
    exit 0
fi

shimejictl summon "$SELECTED"
