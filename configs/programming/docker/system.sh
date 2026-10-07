#!/usr/bin/env bash

# forward policy lives in table inet fw: docker's own FORWARD drop would also cut libvirt and lxc bridges; applies on next docker start
install -Dm644 daemon.json /etc/docker/daemon.json
systemctl enable docker.socket

unit_install docker-prune.service
systemctl enable docker-prune.service
