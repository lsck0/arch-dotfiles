#!/bin/env bash

set -ex

sudo systemctl enable nix-daemon

mkdir -p ${HOME}/.config/nix
ln -sf ${PWD}/nix.conf ${HOME}/.config/nix/nix.conf

sudo nix-channel --add https://nixos.org/channels/nixpkgs-unstable
sudo nix-channel --update
