#!/usr/bin/env bash

# wsl runs microsoft's kernel, these host-hardening keys do not exist there
[[ "$FORM_FACTOR" != wsl ]] || exit 0

install -Dm644 sysctl-hardening.conf /etc/sysctl.d/99-hardening.conf
# systemd-sysctl, not sysctl -p: only it expands the conf.* globs
/usr/lib/systemd/systemd-sysctl /etc/sysctl.d/99-hardening.conf

# blacklist attack-surface kernel modules (applies at the next modprobe; already-loaded ones are left alone)
install -Dm644 modprobe-hardening.conf /etc/modprobe.d/hardening.conf
