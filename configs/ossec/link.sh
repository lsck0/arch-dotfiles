#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if [[ ! -d /var/lib/ossec-hids ]]; then
    exit 0
fi

set -e

# the quickshell system panel reads the alert log; group membership needs a re-login
getent group ossec-alerts >/dev/null || sudo groupadd -r ossec-alerts
id -nG "$USER" | tr ' ' '\n' | grep -qx ossec-alerts || sudo gpasswd -a "$USER" ossec-alerts

sudo install -Dm644 alerts-acl.conf /etc/tmpfiles.d/ossec-alerts.conf
sudo systemd-tmpfiles --create /etc/tmpfiles.d/ossec-alerts.conf
