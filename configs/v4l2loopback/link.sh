#!/usr/bin/env bash

if ! command -v v4l2-ctl >/dev/null 2>&1; then
    exit 0
fi

set -ex

sudo ln -sf ${PWD}/v4l2loopback.conf /etc/modules-load.d/v4l2loopback.conf
sudo ln -sf ${PWD}/v4l2loopback-options.conf /etc/modprobe.d/v4l2loopback.conf
