#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -euo pipefail

# wallets live in the syncthing folder so the homelab and its offsite backup hold them; the .keys files stay password-encrypted
wallets="${HOME}/sync/monero"
settings="${HOME}/.config/feather/settings.json"
mkdir -p "$wallets" "$(dirname "$settings")"
[[ -s "$settings" ]] || echo '{}' >"$settings"
jq --arg dir "$wallets" '.walletDirectory = $dir' "$settings" >"${settings}.tmp"
mv "${settings}.tmp" "$settings"
