#!/bin/env bash

set -ex

mkdir -p ${HOME}/.config/nix
ln -sf ${PWD}/nix.conf ${HOME}/.config/nix/nix.conf
