#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

mkdir -p "${HOME}/sync" "${HOME}/vault"
mkdir -p "${HOME}/.local/bin"
ln -sfn "${PWD}/veracrypt-vault.sh" "${HOME}/.local/bin/veracrypt-vault"

# the password prompt needs a tty
if [ ! -e "${HOME}/sync/vault.hc" ]; then
    if [ -t 0 ] && [ -t 1 ]; then
        "${PWD}/veracrypt-vault.sh" create
    else
        echo "veracrypt-vault: no TTY; create the 1G container later with: veracrypt-vault create" >&2
    fi
fi
