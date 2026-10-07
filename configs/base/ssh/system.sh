#!/usr/bin/env bash

# hardened baseline for every machine: real sshd on knocked 2222, no password, no root password login, so a keyless
# user has no remote ssh surface (console login still works)
install -Dm644 10-hardening.conf /etc/ssh/sshd_config.d/10-hardening.conf
# no host keys before sshd's first start, and sshd -t needs them
ssh-keygen -A
systemctl enable sshd.service
# a config sshd rejects never replaces the running one
sshd -t
systemctl reload-or-restart sshd
