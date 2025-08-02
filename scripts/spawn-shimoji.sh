#!/bin/bash

set -e

SELECTED=$(shimejictl list | sed '1d; s/^[0-9]\+: //' | paste -sd '\n' - | walker --stream --dmenu)

if [[ "$SELECTED" == "CNCLD" || -z "$SELECTED" ]]; then
    exit 0
fi

shimejictl summon "$SELECTED"
