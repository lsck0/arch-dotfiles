#!/usr/bin/env bash

# applies with or without zram: a build cannot evict the desktop's hot pages before oomd's 20s window sees pressure
if [[ -e /sys/kernel/mm/lru_gen/min_ttl_ms ]]; then
    file_update mglru-tmpfiles.conf /etc/tmpfiles.d/mglru.conf || true
    systemd-tmpfiles --create /etc/tmpfiles.d/mglru.conf
fi

# swappiness 150 only pays off with zram; without the generator a disk swap would get it
if [[ ! -x /usr/lib/systemd/system-generators/zram-generator ]]; then
    rm -f /etc/sysctl.d/99-zram.conf
    exit 0
fi

install -Dm644 sysctl-zram.conf /etc/sysctl.d/99-zram.conf
install -Dm644 zram-generator.conf /etc/systemd/zram-generator.conf
