#!/usr/bin/env bash

# pulls the owner's own issue trackers
profile_has identity || exit 0

mkdir -p "${HOME}/.local/state/bugwarrior"
link_into "${HOME}/.config/bugwarrior" bugwarrior.toml
