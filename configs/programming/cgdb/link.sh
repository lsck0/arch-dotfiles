#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

mkdir -p "${HOME}/.cgdb"
ln -sfn "${PWD}/cgdbrc" "${HOME}/.cgdb/cgdbrc"
