#!/bin/env bash

set -ex

mkdir -p ${HOME}/.config/
ln -sf ${PWD}/multi_export_oodwaita.json ${HOME}/.config/oomox/export_config/
ln -sf ${PWD}/multi_export_oomox_classic.json ${HOME}/.config/oomox/export_config/
