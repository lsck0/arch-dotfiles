#!/usr/bin/env bash

set -ex

mkdir -p ${HOME}/.config/VSCodium/User
ln -sf ${PWD}/settings.json ${HOME}/.config/VSCodium/User/settings.json
