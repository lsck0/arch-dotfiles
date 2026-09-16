#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v v4l2-ctl >/dev/null 2>&1; then
    exit 0
fi

set -ex

sudo ln -sfn ${PWD}/v4l2loopback.conf /etc/modules-load.d/v4l2loopback.conf
sudo ln -sfn ${PWD}/v4l2loopback-options.conf /etc/modprobe.d/v4l2loopback.conf
