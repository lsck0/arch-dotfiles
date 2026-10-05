#!/usr/bin/env bash
# json array of every toggle-*.sh as {name, label, on}: the one walker behind menu.sh and the quickshell toggles widget
# a label starting with ● is on, ○ is off, anything else (font, scale) is a setting and reads as off
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

# each label runs once, all at the same time; a line is one atomic pipe write, jq restores the order
for script in toggle-*.sh; do
    {
        name=${script#toggle-}
        name=${name%.sh}
        line=$("./$script" label 2>/dev/null) || line="○ $name (error)"
        printf '%s\t%s\n' "$name" "${line%%$'\n'*}"
    } &
done | jq -Rnc '[inputs | split("\t") | {name: .[0], on: (.[1] | startswith("●")), label: (.[1] | sub("^[●○] "; "") | sub(" \\((on|off)\\)$"; ""))}] | sort_by(.name)'
