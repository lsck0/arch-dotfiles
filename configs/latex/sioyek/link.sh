#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

mkdir -p "$HOME/.config/sioyek"
ln -sfn "${PWD}/prefs_user.config" "$HOME/.config/sioyek/prefs_user.config"
ln -sfn "${PWD}/keys_user.config" "$HOME/.config/sioyek/keys_user.config"
