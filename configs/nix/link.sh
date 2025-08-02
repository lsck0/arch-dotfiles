#!/bin/env bash

set -ex

mkdir -p ${HOME}/.config/nix
ln -sf ${PWD}/nix.conf ${HOME}/.config/nix/nix.conf

sudo nix-channel --add https://nixos.org/channels/nixpkgs-unstable
sudo nix-channel --update
