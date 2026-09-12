#!/usr/bin/env bash

if [[ ! -f ${PWD}/config.json ]]; then
    exit 0
fi

set -ex

sudo ln -sf ${PWD}/config.json /var/lib/portmaster/config.json
