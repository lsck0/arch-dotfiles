#!/usr/bin/env bash

mkdir -p "${HOME}/sync" "${HOME}/vault"
link_commands veracrypt-vault.sh

# the password prompt needs a terminal, and link.sh never has one (stdin /dev/null): only the hint
if [[ ! -e "${HOME}/sync/vault.hc" ]]; then
    echo "veracrypt-vault: no container yet; create the 1G one in a terminal with: veracrypt-vault create" >&2
fi
