#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

# the AUR vkbasalt and lib32-vkbasalt packages ship one layer manifest each
if ! compgen -G "/usr/share/vulkan/implicit_layer.d/vkBasalt*.json" >/dev/null; then
    exit 0
fi

set -e

mkdir -p "${HOME}/.config/vkBasalt"
ln -sfn "${PWD}/vkBasalt.conf" "${HOME}/.config/vkBasalt/vkBasalt.conf"
