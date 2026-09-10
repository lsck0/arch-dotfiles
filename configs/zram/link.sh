#!/usr/bin/env bash

set -ex

sudo ln -sf ${PWD}/zram-generator.conf /etc/systemd/zram-generator.conf

sudo mkdir -p /etc/sysctl.d
sudo ln -sf ${PWD}/sysctl-zram.conf /etc/sysctl.d/99-zram.conf
