#!/usr/bin/env bash

set -euo pipefail

# wallets live in the syncthing folder so the homelab and its offsite backup hold them; the .keys files stay password-encrypted
wallets="${HOME}/sync/monero"
mkdir -p "$wallets"
json_update "${HOME}/.config/feather/settings.json" --arg dir "$wallets" '.walletDirectory = $dir'
