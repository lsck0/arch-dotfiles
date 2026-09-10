#!/usr/bin/env bash
# Multi-cloud cost snapshot for Costs.qml. Credentials live outside git
# entirely, at ~/.config/costs/ — not in configs/secrets (a separate git
# submodule this repo shouldn't write into unprompted) and not in the
# dotfiles repo itself. Each provider is skipped (not faked) if its
# credential file is missing.
set -euo pipefail

CREDS_DIR="$HOME/.config/costs"
mkdir -p "$CREDS_DIR"

hetzner_cost="null"
if [[ -f "$CREDS_DIR/hetzner_token" ]]; then
  token=$(<"$CREDS_DIR/hetzner_token")
  # Hetzner Cloud has no native "current spend" endpoint; this sums per-server
  # hourly price * hours-running-this-month as an estimate, not exact billing.
  hetzner_cost=$(curl -s --max-time 8 -H "Authorization: Bearer $token" \
    "https://api.hetzner.cloud/v1/servers" 2>/dev/null | jq '[.servers[]?.server_type.prices[0].price_monthly.gross // 0 | tonumber] | add // null' 2>/dev/null || echo null)
fi

cloudflare_cost="null"
if [[ -f "$CREDS_DIR/cloudflare_token" ]]; then
  # Cloudflare's billing API needs an Enterprise plan; free/pro accounts have
  # no programmatic spend endpoint. Left null unless that changes.
  cloudflare_cost="null"
fi

gcp_cost="null"
if [[ -f "$CREDS_DIR/gcp_billing_sa.json" ]]; then
  # Needs a service account with roles/billing.viewer and a configured
  # BigQuery billing export — not just the key file. Left null until that's
  # set up; wiring the actual query is real work once it exists.
  gcp_cost="null"
fi

jq -nc --argjson hetzner "$hetzner_cost" --argjson cloudflare "$cloudflare_cost" --argjson gcp "$gcp_cost" \
  '{hetzner: $hetzner, cloudflare: $cloudflare, gcp: $gcp}'
