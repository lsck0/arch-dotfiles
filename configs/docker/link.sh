#!/usr/bin/env bash

set -ex

if ! command -v docker >/dev/null 2>&1; then
    exit 0
fi

sudo systemctl enable docker.socket

sudo mkdir -p /etc/cron.daily

sudo ln -sf ${PWD}/docker-prune-job.sh /etc/cron.daily/docker-prune-job

sudo gpasswd -a $USER docker
