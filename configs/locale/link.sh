#!/usr/bin/env bash

set -ex

# enable german locale
sudo sed -i 's/^# *\(de_DE\.UTF-8 UTF-8\)/\1/' /etc/locale.gen

sudo locale-gen
