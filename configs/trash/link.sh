#!/usr/bin/env bash

set -ex

if ! command -v trash-empty >/dev/null 2>&1; then
    exit 0
fi

sudo mkdir -p /etc/cron.daily

sudo ln -sf ${PWD}/trash-clean-job.sh /etc/cron.daily/trash-clean-job
