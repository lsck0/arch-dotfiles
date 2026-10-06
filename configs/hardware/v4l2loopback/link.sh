#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

sudo install -m644 v4l2loopback.conf /etc/modules-load.d/v4l2loopback.conf
sudo install -m644 v4l2loopback-options.conf /etc/modprobe.d/v4l2loopback.conf
