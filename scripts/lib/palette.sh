# shellcheck shell=bash
# the shared pywal prelude the shell theme generators source; keep in step with scripts/lib/palette.py (its python twin)
# and quickshell Commons/Color.qml. sourced, so a missing colors.json or jq exits the generator cleanly: nothing to theme

COLORS_JSON="$HOME/.cache/wal/colors.json"
[[ -f "$COLORS_JSON" ]] || exit 0
command -v jq >/dev/null || exit 0

# j <filter>: that filter over wal's colors.json
j() { jq -r "$1" "$COLORS_JSON"; }

bg=$(j '.special.background')
fg=$(j '.special.foreground')
read -r c0 c1 c2 c3 c4 c5 c6 c7 c8 c9 c10 c11 c12 c13 c14 c15 < <(
    jq -r '[range(16) as $i | .colors["color\($i)"]] | @tsv' "$COLORS_JSON"
)
