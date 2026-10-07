#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if [[ ! -x /usr/lib/systemd/system-generators/zram-generator ]]; then
    sudo rm -f /etc/sysctl.d/99-zram.conf
    exit 0
fi

set -e

sudo mkdir -p /etc/sysctl.d

sudo install -m644 sysctl-zram.conf /etc/sysctl.d/99-zram.conf
sudo install -m644 zram-generator.conf /etc/systemd/zram-generator.conf
