#!/bin/bash
# Update all the things

set -xe

echo "ARE U SURE?"
read -p "Type 'y' to continue: " confirm
if [ "$confirm" != "y" ]; then
    echo "Aborting update."
    exit 1
fi

yay -Syyu --noconfirm
nix-channel --update
rustup update
cargo install-update -a
rtx upgrade
