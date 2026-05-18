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

# language toolchains

mise upgrade

rustup update
cargo install-update -a

opam update
opam upgrade

ghcup upgrade
ghcup install cabal latest
ghcup install ghc latest
ghcup install hls latest
ghcup install stack latest

# userland

yes | hyprpm update -f

protonup -y

tldr --update_cache

~/.tmux/plugins/tpm/bin/update_plugins all

expect -c '
  spawn doom upgrade --aot
  expect "(y or n)" { send "n\r" }
  expect "(y or n)" { send "y\r" }
  expect eof
'

nvim --headless "+Lazy! sync" +MasonUpdate +TSUpdate +qa
