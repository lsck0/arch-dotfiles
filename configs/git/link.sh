#!/usr/bin/env bash

if ! command -v git >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p ${HOME}/.config/git

if command -v git-lfs >/dev/null 2>&1; then
    git lfs install
fi

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
git config --global merge.conflictStyle zdiff3
if command -v mergiraf >/dev/null 2>&1; then
    mergiraf languages --gitattributes > ${HOME}/.config/git/attributes
    git config --global merge.mergiraf.name "mergiraf"
    git config --global merge.mergiraf.driver "mergiraf merge --git %O %A %B -s %S -x %X -y %Y -p %P -l %L"
fi

# jj deez
if command -v jj >/dev/null 2>&1; then
    jj config set --user user.name "Luca Sandrock"
    jj config set --user user.email "luca.sandrock@proton.me"
    jj config set --user ui.default-command log
fi
