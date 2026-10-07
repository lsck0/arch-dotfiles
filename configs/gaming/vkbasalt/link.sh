#!/usr/bin/env bash

# the AUR vkbasalt and lib32-vkbasalt packages ship one layer manifest each
compgen -G "/usr/share/vulkan/implicit_layer.d/vkBasalt*.json" >/dev/null || exit 0

link_into "${HOME}/.config/vkBasalt" vkBasalt.conf
