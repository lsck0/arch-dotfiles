#!/bin/env bash

set -ex

sudo mkdir -p /etc/cron.daily
sudo ln -sf ${PWD}/docker-prune-job.sh /etc/cron.daily/docker-prune-job
