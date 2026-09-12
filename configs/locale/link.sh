#!/usr/bin/env bash

if ! command -v locale-gen >/dev/null 2>&1; then
    exit 0
fi

set -ex

sudo sed -i 's/^# *\(de_DE\.UTF-8 UTF-8\)/\1/' /etc/locale.gen
sudo sed -i 's/^# *\(en_US\.UTF-8 UTF-8\)/\1/' /etc/locale.gen

sudo locale-gen
