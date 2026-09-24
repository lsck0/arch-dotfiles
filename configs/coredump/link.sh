#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1
set -ex
sudo mkdir -p /etc/systemd/coredump.conf.d
sudo ln -sfn "${PWD}/10-storage.conf" /etc/systemd/coredump.conf.d/10-storage.conf
sudo systemctl daemon-reload
