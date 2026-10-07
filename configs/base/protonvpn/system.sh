#!/usr/bin/env bash

# auto-vpn and the protonvpn toggle stop portmaster while the tunnel is up; polkit grants it to wheel without a password
install -Dm644 49-portmaster.rules /etc/polkit-1/rules.d/49-portmaster.rules
