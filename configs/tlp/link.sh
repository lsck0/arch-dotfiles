#!/usr/bin/env bash

if ! command -v tlp >/dev/null 2>&1; then
    exit 0
fi

set -ex

sudo systemctl enable tlp.service

if compgen -G '/sys/class/power_supply/BAT*' >/dev/null; then
    conf=bat.tlp.conf
else
    conf=ac-only.tlp.conf
fi

sudo ln -sf "${PWD}/${conf}" /etc/tlp.conf
