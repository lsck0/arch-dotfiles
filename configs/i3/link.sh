#!/bin/env bash

set -ex

mkdir -p ${HOME}/.config/i3
ln -sf ${PWD}/config ${HOME}/.config/i3/config
