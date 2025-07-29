#!/bin/env bash

set -ex

mkdir -p ${HOME}/.local/share/Steam/steamui/skins/
ln -sf ${PWD}/NEVKO-UI ${HOME}/.local/share/Steam/steamui/skins/Steam
