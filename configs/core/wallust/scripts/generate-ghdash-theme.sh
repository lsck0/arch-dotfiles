#!/usr/bin/env bash
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
# rewrites the theme.colors block of gh-dash/config.yml in place
set -euo pipefail

CONFIG="$DOTFILES/configs/programming/gh-dash/config.yml"
source "$DOTFILES/scripts/lib/palette.sh"
[[ -f "$CONFIG" ]] || exit 0

accent="$c4"

# bg mixed 12% toward accent
selected=$(python3 - "$bg" "$accent" <<'PY'
import sys
def h(x): x=x.lstrip('#'); return [int(x[i:i+2],16) for i in (0,2,4)]
a,b=h(sys.argv[1]),h(sys.argv[2])
print('#%02x%02x%02x'%tuple(round(a[i]+(b[i]-a[i])*0.12) for i in range(3)))
PY
)

python3 - "$CONFIG" "${fg,,}" "${accent,,}" "${bg,,}" "${c8,,}" "${c3,,}" "${c2,,}" "${selected,,}" \
    "${c4,,}" "${c8,,}" "${c0,,}" <<'PY'
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
    # replace up to the next `  ui:` key
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
