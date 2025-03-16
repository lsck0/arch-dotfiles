#!/bin/env bash

set -ex

mkdir -p ${HOME}/.config/i3status
ln -sf ${PWD}/config ${HOME}/.config/i3status/config
