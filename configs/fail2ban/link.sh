#!/usr/bin/env bash


if ! command -v fail2ban-client >/dev/null 2>&1; then
    exit 0
fi

set -ex

sudo mkdir -p /etc/fail2ban

sudo ln -sf ${PWD}/jail.local /etc/fail2ban/jail.local

sudo systemctl enable fail2ban.service
