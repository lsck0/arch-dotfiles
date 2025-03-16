#!/bin/env bash

set -ex

mkdir -p ${HOME}/.config/picom
ln -sf ${PWD}/config ${HOME}/.config/picom/picom.conf
