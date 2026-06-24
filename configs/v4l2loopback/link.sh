#!/usr/bin/env bash

set -ex

sudo ln -sf ${PWD}/v4l2loopback.conf /etc/modules-load.d/v4l2loopback.conf
sudo ln -sf ${PWD}/v4l2loopback-options.conf /etc/modprobe.d/v4l2loopback.conf
