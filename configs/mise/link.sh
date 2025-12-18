#!/usr/bin/env bash

set -ex

ln -sf ${PWD}/mise.toml ${HOME}/.mise.toml

mise trust ${HOME}/.mise.toml
