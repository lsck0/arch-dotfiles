#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

lines=()
on_count=0
while IFS= read -r script; do
    line=$("$script" label)
    lines+=("$line")
    [[ "$line" == "●"* ]] && on_count=$((on_count + 1))
done < <(find . -maxdepth 1 -name 'toggle-*.sh' | sort)

tooltip=$(printf '%s\n' "${lines[@]}")
# -c: kept single-line for historical reasons (waybar's custom-module exec
# parsed output line by line). quickshell's Toggles widget is the only caller
# now and does not care, but a one-line object stays cheap to consume.
jq -nc --arg text "⚙ $on_count" --arg tooltip "$tooltip" '{text: $text, tooltip: $tooltip}'
