#!/usr/bin/env bash

set -e

ZSH_PATH=$(command -v zsh || true)
if [[ -n "$ZSH_PATH" ]] && grep -qx "$ZSH_PATH" /etc/shells; then
    sudo chsh "$USER" -s "$ZSH_PATH"
fi

getent group libvirt >/dev/null && sudo usermod -aG libvirt "$USER" || echo "skip: libvirt group not present" >&2

if command -v wireshark >/dev/null 2>&1; then
    sudo usermod -aG wireshark "$USER"
fi

# polkit lets the gamemode group set cpu governor and gpu performance level without a prompt
if command -v gamemoded >/dev/null 2>&1; then
    sudo usermod -aG gamemode "$USER"
fi
