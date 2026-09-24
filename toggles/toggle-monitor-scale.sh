#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# Monitor scale, applied live then persisted to hyprland_monitors.lua.

MONITORS_LUA="$HOME/projects/arch-dotfiles/configs/hyprland/hyprland_monitors.lua"

# Live geometry for one output, as "mode position scale".
monitor_info() {
    hyprctl monitors -j 2>/dev/null | python3 -c "
import json, sys
name = sys.argv[1]
for m in json.load(sys.stdin):
    if m['name'] == name:
        print(f\"{m['width']}x{m['height']}@{m['refreshRate']:.5f}\", f\"{m['x']}x{m['y']}\", m['scale'])
        break
" "$1"
}

list_monitors() {
    hyprctl monitors -j 2>/dev/null | python3 -c "
import json, sys
for m in json.load(sys.stdin):
    print(f\"{m['name']}\t{m['width']}x{m['height']}@{m['refreshRate']:.2f}\t{m['scale']}\")
"
}

default_monitor() {
    hyprctl monitors -j 2>/dev/null | python3 -c "
import json, sys
ms = json.load(sys.stdin)
if ms: print(ms[0]['name'])
"
}

# Rewrite scale in the matching hl.monitor block (python, not sed: value sits below the key).
persist() {
    python3 - "$MONITORS_LUA" "$1" "$2" <<'PY'
import re, sys
path, name, scale = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path).read()

def repl(m):
    block = m.group(0)
    if re.search(r'output\s*=\s*"%s"' % re.escape(name), block) is None:
        return block
    return re.sub(r'scale\s*=\s*[0-9.]+', 'scale = %s' % scale, block)

out, n = re.subn(r'hl\.monitor\(\{.*?\}\)', repl, src, flags=re.S), None
new = out[0]
if new == src:
    print("no matching hl.monitor block for %s — not persisted" % name, file=sys.stderr)
    sys.exit(2)
open(path, 'w').write(new)
PY
}

apply_scale() {
    local name=$1 scale=$2 mode position current
    read -r mode position current <<<"$(monitor_info "$name")"
    if [[ -z "${mode:-}" ]]; then
        echo "unknown monitor: $name" >&2
        return 1
    fi

    # apply live first
    local out
    out=$(hyprctl eval "hl.monitor({output=\"$name\", mode=\"$mode\", position=\"$position\", scale=$scale})" 2>&1 || true)
    if [[ "$out" != *ok* ]]; then
        echo "hyprctl rejected the scale: $out" >&2
        return 1
    fi

    # confirm the compositor took it before persisting: a fractional scale
    sleep 0.4
    local applied
    applied=$(monitor_info "$name" | awk '{print $3}')
    if [[ -z "$applied" ]]; then
        echo "monitor disappeared after apply" >&2
        return 1
    fi
    if ! awk -v a="$applied" -v b="$scale" 'BEGIN { exit !(a - b < 0.01 && b - a < 0.01) }'; then
        echo "hyprland adjusted the scale to $applied (asked for $scale); persisting the real value" >&2
        scale=$applied
    fi

    persist "$name" "$scale" || return 1
    toggle_set monitor-scale "$name=$scale"
    toggle_notify -a Toggles "Monitor scale" "$name at ${scale}x"
}

usage() {
    echo "usage: $(basename "$0") {get [monitor]|label|list|set <scale> [monitor]}" >&2
}

case "${1:-label}" in
get)
    m=${2:-$(default_monitor)}
    monitor_info "$m" | awk '{print $3}'
    ;;
label)
    m=$(default_monitor)
    echo "󰍹 Scale: $m $(monitor_info "$m" | awk '{print $3}')x"
    ;;
list) list_monitors ;;
set)
    [[ $# -ge 2 ]] || { usage; exit 1; }
    [[ $2 =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "scale must be a number" >&2; exit 1; }
    apply_scale "${3:-$(default_monitor)}" "$2"
    ;;
*) usage; exit 1 ;;
esac
