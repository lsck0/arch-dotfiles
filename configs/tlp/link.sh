#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

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

sudo ln -sfn "${PWD}/${conf}" /etc/tlp.conf
