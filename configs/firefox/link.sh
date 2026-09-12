#!/usr/bin/env bash

if [[ ! -d ${HOME}/.config/mozilla/firefox ]]; then
    exit 0
fi

set -ex

# fix pywalfox not seeing configs
ln -sfn ${HOME}/.config/mozilla/firefox ${HOME}/.config/firefox
