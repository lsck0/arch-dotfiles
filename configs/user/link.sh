#!/usr/bin/env bash

set -ex

sudo chsh $USER -s /bin/zsh

sudo gpasswd -a $USER docker

sudo usermod -aG wireshark,libvirt $USER
