#!/usr/bin/env bash

install -Dm644 10-storage.conf /etc/systemd/coredump.conf.d/10-storage.conf
# sorts before systemd.conf, so its age wins for the coredump directory
install -Dm644 coredump-tmpfiles.conf /etc/tmpfiles.d/coredump.conf
systemctl daemon-reload
