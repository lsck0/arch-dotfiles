#!/bin/bash
# Update all the things

set -xe

yay -Syyu
nix-channel --update
rustup self update
rustup update
cargo install-update -a
rtx upgrade
