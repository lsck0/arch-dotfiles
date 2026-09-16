#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if [[ ! -x /usr/lib/systemd/system-generators/zram-generator ]]; then
    exit 0
fi

set -ex

sudo mkdir -p /etc/sysctl.d

sudo ln -sfn ${PWD}/sysctl-zram.conf /etc/sysctl.d/99-zram.conf
sudo ln -sfn ${PWD}/zram-generator.conf /etc/systemd/zram-generator.conf
