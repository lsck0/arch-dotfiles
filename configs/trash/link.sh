#!/usr/bin/env bash

set -ex

sudo mkdir -p /etc/cron.daily
sudo ln -sf ${PWD}/trash-clean-job.sh /etc/cron.daily/trash-clean-job
