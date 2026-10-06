#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

ln -sfn "${PWD}" "$HOME/.config/uwsm"
