#!/usr/bin/env bash

set -ex

git config --global user.name "Luca Sandrock"
git config --global user.email "luca.sandrock@proton.me"
git config --global credential.helper store
git config --global init.defaultBranch master
git config --global pull.rebase true
git config --global --type bool push.autoSetupRemote true
git config --global core.pager delta
git config --global interactive.diffFilter 'delta --color-only'
git config --global merge.conflictStyle zdiff3
git config --global delta.dark true
git config --global delta.line-numbers true
git config --global delta.navigate true
git config --global delta.side-by-side true

git lfs install

jj config set --user user.name "Luca Sandrock"
jj config set --user user.email "luca.sandrock@proton.me"
