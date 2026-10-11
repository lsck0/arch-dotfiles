#!/usr/bin/env bash

[[ -d /var/lib/ossec-hids ]] || exit 0

# the quickshell system panel reads the alert log; group membership needs a re-login
group_add_admins ossec-alerts

systemctl enable ossec-server.target

install -Dm644 alerts-acl.conf /etc/tmpfiles.d/ossec-alerts.conf
systemd-tmpfiles --create /etc/tmpfiles.d/ossec-alerts.conf
