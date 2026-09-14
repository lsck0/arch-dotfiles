#!/usr/bin/env bash

if ! command -v docker >/dev/null 2>&1; then
    exit 0
fi

set -ex

sudo systemctl enable docker.socket

sudo mkdir -p /etc/cron.daily

sudo ln -sfn ${PWD}/docker-prune-job.sh /etc/cron.daily/docker-prune-job

sudo gpasswd -a $USER docker
