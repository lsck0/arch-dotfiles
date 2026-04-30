#!/usr/bin/env bash
# Update all the things

set -x

echo "ARE U SURE?"
read -p "Type 'y' to continue: " confirm
if [ "$confirm" != "y" ]; then
    echo "Aborting update."
    exit 1
fi

# system packages

yay -Syyu --rebuildall --answerclean A --answerdiff N --noconfirm
flatpak update --assumeyes
nix-channel --update
cargo install-update -a

# language toolchains

rustup update

opam update
opam upgrade

ghcup upgrade
ghcup install cabal latest
ghcup install ghc latest
ghcup install hls latest
ghcup install stack latest

mise upgrade

# userland

yes | hyprpm update -f

~/.tmux/plugins/tpm/bin/update_plugins all
tldr --update_cache
nvim --headless "+Lazy! sync" +MasonUpdate +TSUpdate +qa
doom upgrade
