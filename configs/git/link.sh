#!/usr/bin/env bash

if ! command -v git >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p ${HOME}/.config/git
git lfs install

# basic
git config --global user.name "Luca Sandrock"
git config --global user.email "luca.sandrock@proton.me"
git config --global credential.helper store
git config --global init.defaultBranch master
git config --global pull.rebase true
git config --global --type bool push.autoSetupRemote true

# diff
git config --global core.pager delta
git config --global interactive.diffFilter 'delta --color-only'
git config --global delta.dark true
git config --global delta.line-numbers true
git config --global delta.navigate true
git config --global delta.side-by-side true

# merging
mergiraf languages --gitattributes > ${HOME}/.config/git/attributes
git config --global merge.conflictStyle zdiff3
git config --global merge.mergiraf.name "mergiraf"
git config --global merge.mergiraf.driver "mergiraf merge --git %O %A %B -s %S -x %X -y %Y -p %P -l %L"

# jj deez
jj config set --user user.name "Luca Sandrock"
jj config set --user user.email "luca.sandrock@proton.me"
