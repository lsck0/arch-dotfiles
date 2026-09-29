#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1
set -ex

# proxychains-ng reads ./proxychains.conf, then ~/.proxychains/proxychains.conf,
# then /etc. Link the user copy so `proxychains4 <tool>` works from any dir.
mkdir -p "${HOME}/.proxychains"
ln -sfn "${PWD}/proxychains.conf" "${HOME}/.proxychains/proxychains.conf"

# Per-engagement egress config (host + authorized exit IP) is not in the repo.
# Seed a sample the first time; egress.sh reads ~/.config/egress/config.
mkdir -p "${HOME}/.config/egress"
if [ ! -e "${HOME}/.config/egress/config" ]; then
    install -m 600 egress.config.sample "${HOME}/.config/egress/config"
fi
