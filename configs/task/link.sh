#!/usr/bin/env bash

set -ex

mkdir -p ~/.task/hooks
mkdir -p ~/.timewarrior

sudo cp /usr/share/doc/timew/ext/on-modify.timewarrior ~/.task/hooks/
sudo chmod +x ~/.task/hooks/on-modify.timewarrior
