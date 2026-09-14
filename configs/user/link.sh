#!/usr/bin/env bash

set -ex

ZSH_PATH=$(command -v zsh || true)
if [[ -n "$ZSH_PATH" ]] && grep -qx "$ZSH_PATH" /etc/shells; then
    sudo chsh "$USER" -s "$ZSH_PATH"
fi

getent group libvirt >/dev/null && sudo usermod -aG libvirt $USER || echo "skip: libvirt group not present" >&2

if command -v wireshark >/dev/null 2>&1; then
    sudo usermod -aG wireshark $USER
fi
