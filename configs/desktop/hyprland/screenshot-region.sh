#!/usr/bin/env bash
# region screenshot to the clipboard; slurp in the pywal palette instead of its white tint: the screen dimmed with the
# background, the selection outlined in the accent (color4, as quickshell's Colors.accent) and lightly filled
set -euo pipefail

COLORS_JSON="$HOME/.cache/wal/colors.json"
bg="#0b0e14" accent="#39bae6"
if [[ -f "$COLORS_JSON" ]]; then
    read -r bg accent < <(jq -r '"\(.special.background) \(.colors.color4)"' "$COLORS_JSON") || true
fi
# slurp takes rrggbbaa
region=$(slurp -b "${bg#\#}99" -c "${accent#\#}ff" -s "${accent#\#}22" -w 2) || exit 0
grim -g "$region" - | wl-copy
