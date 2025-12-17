#!/usr/bin/env bash

set -ex

mkdir -p ${HOME}/.config/mako
ln -sf ${PWD}/config ${HOME}/.config/mako/config
