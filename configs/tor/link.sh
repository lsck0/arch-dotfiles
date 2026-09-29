#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v tor >/dev/null 2>&1; then
    exit 0
fi

set -ex

# real files in /etc, tor runs as its own user and must not depend on /home
sudo install -m 644 torrc /etc/tor/torrc
sudo install -m 755 tor-router /usr/bin/tor-router
# started by the toron/toroff aliases
sudo install -m 644 tor-router.service /etc/systemd/system/tor-router.service

sudo systemctl daemon-reload
sudo systemctl enable tor.service
sudo systemctl restart tor.service
