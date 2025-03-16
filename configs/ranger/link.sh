#!/bin/env bash

set -ex

mkdir -p ${HOME}/.config/ranger
ln -sf ${PWD}/rc.conf ${HOME}/.config/ranger/rc.conf
