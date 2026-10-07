#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

sudo mkdir -p /etc/systemd/coredump.conf.d
sudo install -m644 10-storage.conf /etc/systemd/coredump.conf.d/10-storage.conf
# sorts before systemd.conf, so its age wins for the coredump directory
sudo install -Dm644 coredump-tmpfiles.conf /etc/tmpfiles.d/coredump.conf
sudo systemctl daemon-reload
