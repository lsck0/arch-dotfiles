#!/usr/bin/env bash

# Start hyprlock with fingerprint authentication only when this user has both
# a real fprintd device and at least one enrolled finger. Package/PAM presence
# alone is not sufficient.
set -euo pipefail

config="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprlock.conf"
if [[ ! -r "$config" ]]; then
  exec hyprlock "$@"
fi

fingerprint_ready=false
if command -v fprintd-list >/dev/null 2>&1; then
  list_output=$(timeout 5s fprintd-list "${USER:?}" 2>/dev/null || true)
  if grep -qE '^found [1-9][0-9]* devices?$' <<<"$list_output" \
      && grep -qE '^ - #[0-9]+: .+' <<<"$list_output"; then
    fingerprint_ready=true
  fi
fi

if "$fingerprint_ready"; then
  exec hyprlock -c "$config" "$@"
fi

# Keep the tracked config unchanged; disable only the fallback invocation's
# fingerprint option when no usable hardware/enrollment is present.
tmp_config=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/hyprlock.XXXXXX.conf")
trap 'rm -f "$tmp_config"' EXIT
sed -E 's/^([[:space:]]*fingerprint:enabled[[:space:]]*=)[[:space:]]*true/\1 false/' \
  "$config" >"$tmp_config"
exec hyprlock -c "$tmp_config" "$@"
