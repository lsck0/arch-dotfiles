#!/usr/bin/env bash
# Update all the things

set -x

echo "ARE U SURE?"
read -p "Type 'y' to continue: " confirm
if [ "$confirm" != "y" ]; then
    echo "Aborting update."
    exit 1
fi

yay -Syyu --rebuildall --answerclean A --answerdiff N --noconfirm
flatpak update --assumeyes
nix-channel --update

rustup update
cargo install-update -a

opam update
opam upgrade

ghcup upgrade
ghcup install cabal latest
ghcup install ghc latest
ghcup install hls latest
ghcup install stack latest

mise upgrade

yes | hyprpm update -f
