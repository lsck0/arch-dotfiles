#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

mkdir -p "${HOME}/.config/qutebrowser"

ln -sfn "${PWD}/config.py" "${HOME}/.config/qutebrowser/config.py"
ln -sfn "${PWD}/startpage.html" "${HOME}/.config/qutebrowser/startpage.html"
