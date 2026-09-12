#!/usr/bin/env bash

if [[ ! -x /usr/lib/systemd/system-generators/zram-generator ]]; then
    exit 0
fi

set -ex

sudo mkdir -p /etc/sysctl.d

sudo ln -sf ${PWD}/sysctl-zram.conf /etc/sysctl.d/99-zram.conf
sudo ln -sf ${PWD}/zram-generator.conf /etc/systemd/zram-generator.conf
