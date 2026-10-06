#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

# pentesting wordlists within reach as ~/.wordlists
[[ -d /usr/share/seclists ]] || exit 0

ln -sfn /usr/share/seclists "${HOME}/.wordlists"
