#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

# lactd idles on its socket and changes nothing until a setting is applied in the gui
sudo systemctl enable --now lactd.service
