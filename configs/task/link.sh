#!/usr/bin/env bash

if ! command -v task >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p ~/.task/hooks
mkdir -p ~/.timewarrior

sudo cp /usr/share/doc/timew/ext/on-modify.timewarrior ~/.task/hooks/
sudo chmod +x ~/.task/hooks/on-modify.timewarrior
