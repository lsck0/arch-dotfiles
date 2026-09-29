#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1
set -ex

mkdir -p "${HOME}/.proxychains"
ln -sfn "${PWD}/proxychains.conf" "${HOME}/.proxychains/proxychains.conf"

# seed the untracked config once
mkdir -p "${HOME}/.config/anonymous-socks"
if [ ! -e "${HOME}/.config/anonymous-socks/config" ]; then
    install -m 600 anonymous-socks.config.sample "${HOME}/.config/anonymous-socks/config"
fi
