#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v nmcli >/dev/null 2>&1; then
    exit 0
fi

set -e

conf=/etc/NetworkManager/NetworkManager.conf
# a restart drops wifi for seconds: only on change, then wait so later link.sh (nvim plugins) have network
if [ "$(readlink "${conf}")" != "${PWD}/NetworkManager.conf" ]; then
    sudo ln -sfn "${PWD}/NetworkManager.conf" "${conf}"
    sudo systemctl restart NetworkManager.service
    nm-online -q --timeout=60 || echo "networkmanager: still offline after 60s" >&2
fi
