#!/usr/bin/env bash

set -euo pipefail

# wallets live in the syncthing folder so the homelab and its offsite backup hold them; the .keys files stay password-encrypted.
# only pointed at, never created: monero/master is a wallet file, and a dir made here on a fresh install before syncthing
# delivered it collides with that file and leaves sync conflicts; syncthing creates the folder with its contents
wallets="${HOME}/sync/monero"
json_update "${HOME}/.config/feather/settings.json" --arg dir "$wallets" '.walletDirectory = $dir'
