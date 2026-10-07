#!/usr/bin/env bash

mkdir -p "${HOME}/sync" "${HOME}/vault"
link_commands veracrypt-vault.sh

# the password prompt needs a tty
if [[ ! -e "${HOME}/sync/vault.hc" ]]; then
    if [[ -t 0 && -t 1 ]]; then
        ./veracrypt-vault.sh create
    else
        echo "veracrypt-vault: no TTY; create the 1G container later with: veracrypt-vault create" >&2
    fi
fi
