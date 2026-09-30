#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

sudo mkdir -p /etc/systemd/coredump.conf.d
sudo install -m644 10-storage.conf /etc/systemd/coredump.conf.d/10-storage.conf
sudo systemctl daemon-reload
