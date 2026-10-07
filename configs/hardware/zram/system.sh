#!/usr/bin/env bash

# swappiness 150 only pays off with zram; without the generator a disk swap would get it
if [[ ! -x /usr/lib/systemd/system-generators/zram-generator ]]; then
    rm -f /etc/sysctl.d/99-zram.conf
    exit 0
fi

install -Dm644 sysctl-zram.conf /etc/sysctl.d/99-zram.conf
install -Dm644 zram-generator.conf /etc/systemd/zram-generator.conf
