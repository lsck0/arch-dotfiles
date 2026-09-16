#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -ex

if ! command -v trash-empty >/dev/null 2>&1; then
    exit 0
fi

sudo mkdir -p /etc/cron.daily

sudo ln -sfn ${PWD}/trash-clean-job.sh /etc/cron.daily/trash-clean-job
