#!/usr/bin/env bash
# multi-cloud cost snapshot
set -euo pipefail

CREDS_DIR="$HOME/.config/costs"
mkdir -p "$CREDS_DIR"

hetzner_cost="null"
if [[ -f "$CREDS_DIR/hetzner_token" ]]; then
  token=$(<"$CREDS_DIR/hetzner_token")
  # no spend endpoint, so estimate from monthly server prices
  hetzner_cost=$(curl -s --max-time 8 -H "Authorization: Bearer $token" \
    "https://api.hetzner.cloud/v1/servers" 2>/dev/null | jq '[.servers[]?.server_type.prices[0].price_monthly.gross // 0 | tonumber] | add // null' 2>/dev/null || echo null)
fi

# cloudflare billing api needs an enterprise plan
cloudflare_cost="null"
# gcp needs a billing.viewer account plus a bigquery billing export
gcp_cost="null"

jq -nc --argjson hetzner "$hetzner_cost" --argjson cloudflare "$cloudflare_cost" --argjson gcp "$gcp_cost" \
  '{hetzner: $hetzner, cloudflare: $cloudflare, gcp: $gcp}'
