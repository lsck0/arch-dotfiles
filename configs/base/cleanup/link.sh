#!/usr/bin/env bash

# runs as the profile owner: expires its generations, the daemon collects the store
command -v nix >/dev/null 2>&1 || exit 0
unit_install nix-gc.service nix-gc.timer
systemctl --user enable --now nix-gc.timer
