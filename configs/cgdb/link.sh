#!/usr/bin/env bash

set -ex

mkdir -p ${HOME}/.cgdb
ln -sf ${PWD}/cgdbrc ${HOME}/.cgdb/cgdbrc
