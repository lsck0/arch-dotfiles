#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

picker=gui
[[ "${1:-}" == "--fzf" ]] && picker=fzf

declare -A LINE_TO_SCRIPT
lines=()
while IFS= read -r script; do
    line=$("$script" label)
    lines+=("$line")
    LINE_TO_SCRIPT["$line"]=$script
done < <(find . -maxdepth 1 -name 'toggle-*.sh' | sort)

if [[ "$picker" == fzf ]]; then
    selected=$(printf '%s\n' "${lines[@]}" | fzf --prompt="Toggles> " --height=~60% --border --header="enter: toggle | esc: cancel")
else
    # scripts/picker.sh (pywal-themed bemenu). Was `walker --dmenu`;
    # walker was removed 2026-09-02.
    selected=$(printf '%s\n' "${lines[@]}" | "$HOME/projects/arch-dotfiles/scripts/picker.sh" -p "Toggles")
fi
[[ -z "${selected:-}" ]] && exit 0

script=${LINE_TO_SCRIPT[$selected]:-}
[[ -n "$script" ]] && exec "$script" toggle
