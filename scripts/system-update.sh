#!/usr/bin/env bash
# Update all the things

set -e

arch-update
flatpak update --assumeyes
nix-channel --update
rustup update
cargo install-update -a
mise upgrade
