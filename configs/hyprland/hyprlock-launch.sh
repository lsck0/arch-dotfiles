#!/usr/bin/env bash

set -euo pipefail

# Issue 29: hyprlock has no built-in single-instance guard, so a lock
# triggered from two paths close together (hypridle's idle timeout AND
# before_sleep_cmd's `loginctl lock-session`, or a manual lock keybind hit
# while an idle-triggered lock is already up) stacks a second ~150-200MB
# hyprlock process on top of the first instead of no-op'ing. Found via `ps`
# showing two hyprlock processes, one 16+ hours old. Bail out early if one is
# already running — the existing instance already has the session locked.
if pgrep -x hyprlock -u "$USER" >/dev/null 2>&1; then
  exit 0
fi

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

tmp_config=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/hyprlock.XXXXXX.conf")
trap 'rm -f "$tmp_config"' EXIT
sed -E 's/^([[:space:]]*fingerprint:enabled[[:space:]]*=)[[:space:]]*true/\1 false/' \
  "$config" >"$tmp_config"
exec hyprlock -c "$tmp_config" "$@"
