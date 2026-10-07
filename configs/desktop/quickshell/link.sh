#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

mkdir -p "${HOME}/.local/bin"
rm -rf "${HOME}/.config/quickshell"
ln -sfn "${PWD}" "${HOME}/.config/quickshell"
for script in "${PWD}"/scripts/*.sh; do
    ln -sfn "$script" "${HOME}/.local/bin/$(basename "$script" .sh)"
done
