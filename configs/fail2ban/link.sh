#!/usr/bin/env bash

set -ex

sudo mkdir -p /etc/fail2ban
sudo ln -sf ${PWD}/jail.local /etc/fail2ban/jail.local

sudo systemctl enable fail2ban.service
