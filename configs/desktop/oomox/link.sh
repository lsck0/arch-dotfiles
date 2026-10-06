#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

mkdir -p "${HOME}/.config/oomox/export_config/"

ln -sfn "${PWD}/multi_export_oodwaita.json" "${HOME}/.config/oomox/export_config/multi_export_oodwaita.json"
ln -sfn "${PWD}/multi_export_oomox_classic.json" "${HOME}/.config/oomox/export_config/multi_export_oomox_classic.json"
