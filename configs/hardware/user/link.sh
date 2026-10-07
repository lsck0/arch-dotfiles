#!/usr/bin/env bash

set -e

if command -v wireshark >/dev/null 2>&1; then
    sudo usermod -aG wireshark "$USER"
fi
