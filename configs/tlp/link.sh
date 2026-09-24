#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v tlp >/dev/null 2>&1; then
    exit 0
fi

set -ex

sudo systemctl enable tlp.service

if compgen -G '/sys/class/power_supply/BAT*' >/dev/null; then
    conf=bat.tlp.conf
else
    conf=ac-only.tlp.conf
fi

# Copy, not symlink: tlp.service is sandboxed (ProtectHome) and cannot read a
# config that points into /home, so /etc/tlp.conf must be a real file.
sudo install -m 644 "${PWD}/${conf}" /etc/tlp.conf
sudo systemctl restart tlp
