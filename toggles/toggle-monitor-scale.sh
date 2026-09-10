#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# Monitor scale, applied live and then persisted into
# configs/hyprland/hyprland_monitors.lua so it survives a Hyprland restart.
#
# TWO BUGS IN WHAT THIS REPLACES, both silent:
#
# 1. Display.qml ran `hyprctl keyword monitor <name>,preferred,auto,<scale>`.
#    This repo drives Hyprland from Lua configs, and **`hyprctl keyword` does
#    not work against a non-legacy parser** — it prints "keyword can't work
#    with non-legacy parsers. Use eval." and **exits 0**. So the old scale
#    control did nothing at all while reporting success. `hyprctl eval` with
#    a Lua `hl.monitor{}` call is the form that actually applies.
#
# 2. Even had it worked, `preferred,auto` **discards the monitor's actual
#    mode and position**: it re-derives resolution and refresh from
#    Hyprland's own preference and moves the output to an auto-computed
#    spot. Changing a scale should not silently renegotiate the mode. This
#    reads the live mode and position from `hyprctl monitors -j` and
#    reapplies them alongside the new scale.
#
# Apply-then-persist, in that order and only on success: a scale a monitor
# cannot actually take is recoverable by not having been written to disk yet.

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

# Rewrite `scale = N` inside the hl.monitor block whose output matches.
# Done in python rather than sed because the value lives several lines below
# the key that identifies which block to touch.
persist() {
    python3 - "$MONITORS_LUA" "$1" "$2" <<'PY'
import re, sys
path, name, scale = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path).read()

# Each block is `hl.monitor({ ... })`; find the one whose output matches and
# replace only its scale.
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

    # Live first. `hyprctl eval`, not `hyprctl keyword` — see the header.
    local out
    out=$(hyprctl eval "hl.monitor({output=\"$name\", mode=\"$mode\", position=\"$position\", scale=$scale})" 2>&1 || true)
    if [[ "$out" != *ok* ]]; then
        echo "hyprctl rejected the scale: $out" >&2
        return 1
    fi

    # Confirm the compositor actually took it before writing to disk. A
    # fractional scale that does not divide the mode cleanly gets refused or
    # silently adjusted, and persisting that would make the bad value
    # survive a restart.
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
