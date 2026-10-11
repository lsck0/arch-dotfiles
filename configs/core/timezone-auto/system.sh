#!/usr/bin/env bash

install -Dm644 49-timezone-auto.rules /etc/polkit-1/rules.d/49-timezone-auto.rules
# wsl has no networkmanager (hardware group); NM refuses a group/world-writable dispatcher
if [[ -d /etc/NetworkManager/dispatcher.d ]]; then
    install -o root -g root -m755 nm-dispatcher.sh /etc/NetworkManager/dispatcher.d/85-timezone-auto
fi
