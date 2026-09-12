#!/usr/bin/env bash
# Keep the system timezone matching where the machine actually is.

set -euo pipefail

REPO="$HOME/projects/arch-dotfiles"
TOGGLES="$REPO/toggles"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/toggles"
DISABLED_FLAG="$STATE_DIR/timezone-auto-disabled"

log() { echo "timezone-auto: $*" >&2; }

current_tz() {
    timedatectl show -p Timezone --value 2>/dev/null || true
}

tunnel_up() {
    local t state
    for t in vpn protonvpn tor; do
        [[ -x "$TOGGLES/toggle-$t.sh" ]] || continue
        state=$("$TOGGLES/toggle-$t.sh" get 2>/dev/null || echo off)
        [[ "$state" == "on" ]] && { echo "$t"; return 0; }
    done
    return 1
}

valid_tz() {
    local tz=$1
    [[ "$tz" =~ ^[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+){1,2}$ ]] || return 1
    [[ -f "/usr/share/zoneinfo/$tz" ]]
}

detect_tz() {
    local json tz
    json=$(timeout 10 curl -s --max-time 8 'https://ipapi.co/json/' 2>/dev/null || true)
    if [[ -n "$json" ]]; then
        tz=$(python3 -c "
import json,sys
try:
    print(json.load(sys.stdin).get('timezone') or '')
except Exception:
    print('')
" <<<"$json" 2>/dev/null || true)
        [[ -n "$tz" ]] && { echo "$tz"; return 0; }
    fi
    # Second provider, different operator — one being down or rate-limiting
    # should not mean the timezone silently stops tracking.
    json=$(timeout 10 curl -s --max-time 8 'http://ip-api.com/json/?fields=timezone' 2>/dev/null || true)
    if [[ -n "$json" ]]; then
        tz=$(python3 -c "
import json,sys
try:
    print(json.load(sys.stdin).get('timezone') or '')
except Exception:
    print('')
" <<<"$json" 2>/dev/null || true)
        [[ -n "$tz" ]] && { echo "$tz"; return 0; }
    fi
    return 1
}

apply() {
    local dry=${1:-}
    local cur want tunnel

    if [[ -e "$DISABLED_FLAG" ]]; then
        return 0
    fi

    if tunnel=$(tunnel_up); then
        return 0
    fi

    cur=$(current_tz)
    if ! want=$(detect_tz); then
        return 0
    fi

    if ! valid_tz "$want"; then
        return 0
    fi

    if [[ "$want" == "$cur" ]]; then
        return 0
    fi

    if [[ "$dry" == "--dry-run" ]]; then
        return 0
    fi

    if timedatectl set-timezone "$want"; then
        command -v notify-send >/dev/null &&
            notify-send -a Timezone "Timezone updated" "$cur → $want" || true
        command -v systemctl >/dev/null &&
            systemctl --user try-restart quickshell.service >/dev/null 2>&1 || true
    else
        return 1
    fi
}

usage() {
    echo "usage: $(basename "$0") {apply|check|status|enable|disable}" >&2
}

case "${1:-apply}" in
apply) apply ;;
check) apply --dry-run ;;
status)
    echo "current:  $(current_tz)"
    if t=$(tunnel_up); then echo "tunnel:   $t (detection suppressed)"; else echo "tunnel:   none"; fi
    if [[ -e "$DISABLED_FLAG" ]]; then echo "auto:     disabled"; else echo "auto:     enabled"; fi
    echo "detected: $(detect_tz || echo '(unavailable)')"
    ;;
enable)  mkdir -p "$STATE_DIR"; rm -f "$DISABLED_FLAG"; echo "timezone auto-detection enabled" ;;
disable) mkdir -p "$STATE_DIR"; : >"$DISABLED_FLAG"; echo "timezone auto-detection disabled" ;;
*) usage; exit 1 ;;
esac
