#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

lines=()
on_count=0
while IFS= read -r script; do
    if ! line=$("$script" label 2>/dev/null); then
        line="○ $(basename "$script" .sh | sed 's/^toggle-//') (error)"
    fi
    lines+=("$line")
    [[ "$line" == "●"* ]] && on_count=$((on_count + 1))
done < <(find . -maxdepth 1 -name 'toggle-*.sh' | sort)

tooltip=$(printf '%s\n' "${lines[@]}")
# single-line output: waybar's custom-module exec parsed it line by line
jq -nc --arg text "⚙ $on_count" --arg tooltip "$tooltip" '{text: $text, tooltip: $tooltip}'
