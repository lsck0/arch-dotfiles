#!/usr/bin/env bash

set -ex

git config --global user.email "luca.sandrock@proton.me"
git config --global user.name "Luca Sandrock"
git config --global credential.helper store
git config --global init.defaultBranch master
git config --global pull.rebase true

jj config set --user user.name "Luca Sandrock"
jj config set --user user.email "luca.sandrock@proton.me"
