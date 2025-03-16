#!/bin/env bash

set -ex

mkdir -p ${HOME}/.config/kitty
ln -sf ${PWD}/kitty.conf ${HOME}/.config/kitty/kitty.conf
