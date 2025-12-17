#!/usr/bin/env bash
# Update all the things

set -e

echo "ARE U SURE?"
read -p "Type 'y' to continue: " confirm
if [ "$confirm" != "y" ]; then
    echo "Aborting update."
    exit 1
fi

yay -Syyu --noconfirm --rebuildall --answerclean A
flatpak update --assumeyes
nix-channel --update
rustup update
cargo install-update -a
mise upgrade
