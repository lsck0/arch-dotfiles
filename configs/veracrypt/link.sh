#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v veracrypt >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p "${HOME}/.local/bin"
chmod 755 "${PWD}/veracrypt-vault.sh"
ln -sfn "${PWD}/veracrypt-vault.sh" "${HOME}/.local/bin/veracrypt-vault"
