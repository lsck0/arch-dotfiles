#!/usr/bin/env bash
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

picker=gui
[[ "${1:-}" == "--fzf" ]] && picker=fzf

declare -A LINE_TO_NAME
lines=()
while IFS=$'\t' read -r name line; do
    lines+=("$line")
    LINE_TO_NAME["$line"]=$name
done < <(./status.sh | jq -r '.[] | [.name, (if .on then "● " else "○ " end) + .label] | @tsv')

if [[ "$picker" == fzf ]]; then
    selected=$(printf '%s\n' "${lines[@]}" | fzf --prompt="Toggles> " --height=~60% --border --header="enter: toggle | esc: cancel")
else
    # scripts/picker.sh (pywal-themed bemenu).
    selected=$(printf '%s\n' "${lines[@]}" | "$DOTFILES/scripts/picker.sh" -p "Toggles")
fi
[[ -z "${selected:-}" ]] && exit 0

name=${LINE_TO_NAME[$selected]:-}
[[ -n "$name" ]] && exec "./toggle-$name.sh" toggle
