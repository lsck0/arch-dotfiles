#!/usr/bin/env bash

set -ex

sudo chsh $USER -s /bin/zsh

getent group libvirt >/dev/null && sudo usermod -aG libvirt $USER || echo "skip: libvirt group not present" >&2

if command -v wireshark >/dev/null 2>&1; then
    sudo usermod -aG wireshark $USER
fi
