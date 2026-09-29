#!/usr/bin/env bash
# Rewrites gh-dash's theme.colors block from pywal's colors.json, in place.
# gh-dash re-reads config on launch (no live reload), so this seeds the file.
set -euo pipefail

COLORS_JSON="$HOME/.cache/wal/colors.json"
CONFIG="$HOME/projects/arch-dotfiles/configs/gh-dash/config.yml"

[[ -f "$COLORS_JSON" ]] || exit 0
[[ -f "$CONFIG" ]] || exit 0
command -v jq >/dev/null || exit 0

j() { jq -r "$1" "$COLORS_JSON"; }

bg=$(j '.special.background')
fg=$(j '.special.foreground')
c0=$(j '.colors.color0')
c2=$(j '.colors.color2')
c3=$(j '.colors.color3')
c4=$(j '.colors.color4')
c8=$(j '.colors.color8')

# accent drives secondary text + primary border, matching Color.accent in the bar.
accent="$c4"

# selected background: bg lifted toward the accent so a highlighted row reads.
selected=$(python3 - "$bg" "$accent" <<'PY'
import sys
def h(x): x=x.lstrip('#'); return [int(x[i:i+2],16) for i in (0,2,4)]
a,b=h(sys.argv[1]),h(sys.argv[2])
print('#%02x%02x%02x'%tuple(round(a[i]+(b[i]-a[i])*0.12) for i in range(3)))
PY
)

# Map palette -> gh-dash theme.colors keys, lowercased to match the file.
lc() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
python3 - "$CONFIG" "$(lc "$fg")" "$(lc "$accent")" "$(lc "$bg")" \
    "$(lc "$c8")" "$(lc "$c3")" "$(lc "$c2")" "$(lc "$selected")" \
    "$(lc "$c4")" "$(lc "$c8")" "$(lc "$c0")" <<'PY'
import sys
cfg, primary, secondary, inverted, faint, warning, success, \
    sel, bprimary, bsecondary, bfaint = sys.argv[1:]
block = f"""  colors:
    text:
      primary: "{primary}"
      secondary: "{secondary}"
      inverted: "{inverted}"
      faint: "{faint}"
      warning: "{warning}"
      success: "{success}"
    background:
      selected: "{sel}"
    border:
      primary: "{bprimary}"
      secondary: "{bsecondary}"
      faint: "{bfaint}"
"""
lines = open(cfg).read().splitlines(keepends=True)
out, i, n = [], 0, len(lines)
while i < n:
    # Replace the block from `  colors:` up to the next top-of-theme key `  ui:`.
    if lines[i].startswith("  colors:"):
        out.append(block)
        i += 1
        while i < n and not lines[i].startswith("  ui:"):
            i += 1
        continue
    out.append(lines[i])
    i += 1
open(cfg, "w").write("".join(out))
PY
