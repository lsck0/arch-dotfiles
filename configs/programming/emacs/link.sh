#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

# packages install themselves on first launch (use-package-always-ensure), not here
ln -sfn "${PWD}" "$HOME/.config/emacs"
