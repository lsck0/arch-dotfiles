#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

# forward policy lives in table inet fw: docker's own FORWARD drop would also cut libvirt and lxc bridges; applies on next docker start
sudo install -Dm644 daemon.json /etc/docker/daemon.json
sudo systemctl enable docker.socket

# copied, not linked: pid1 loads units before /home mounts
sudo install -Dm644 docker-prune.service /etc/systemd/system/docker-prune.service
sudo systemctl enable docker-prune.service
