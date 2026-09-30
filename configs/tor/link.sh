#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v tor >/dev/null 2>&1; then
    exit 0
fi

set -e

# real files in /etc, tor runs as its own user and must not depend on /home
sudo install -m 644 torrc /etc/tor/torrc
# /usr/local and a drop-in, the packaged /usr/bin script and unit stay untouched
sudo install -m 755 tor-router /usr/local/bin/tor-router
# started by the toron/toroff aliases
sudo install -Dm 644 tor-router-override.conf /etc/systemd/system/tor-router.service.d/override.conf

sudo systemctl daemon-reload
sudo systemctl enable tor.service
sudo systemctl restart tor.service
