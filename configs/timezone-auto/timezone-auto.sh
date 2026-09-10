#!/usr/bin/env bash
set -euo pipefail

# Keep the system timezone matching where the machine actually is.
#
# This exists because the timezone was wrong and nothing noticed: the system
# read Europe/Berlin while the laptop was in Glasgow, which silently skews
# every timestamp, calendar entry and cron/timer schedule on the box. The
# quickshell clock, the lock screen and the world-clock widget all render
# whatever this says, so they were all wrong together and consistently, which
# is the hardest kind of wrong to spot.
#
# TUNNEL GUARD, and it is the whole reason this is a script rather than one
# curl in a timer. Location here comes from the public IP, so with ProtonVPN,
# WireGuard or Tor up it reports the EXIT NODE's timezone. Setting the clock
# from that would mean connecting to a Dutch exit node silently moved the
# machine to Amsterdam — and then disconnecting would leave it there. So a
# detected tunnel means "do nothing", never "guess". Same reasoning as
# toggles/toggle-weather-location.sh, which documents the identical trap for
# weather.
#
# PRIVACY: the IP-geolocation tier discloses the public IP to a third party
# (ipapi.co), exactly as the weather resolver's last tier does. It is only
# reached when no tunnel is up. `check` and `--dry-run` never set anything, so
# they are safe to run when you only want to look.

REPO="$HOME/projects/arch-dotfiles"
TOGGLES="$REPO/toggles"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/toggles"
DISABLED_FLAG="$STATE_DIR/timezone-auto-disabled"

log() { echo "timezone-auto: $*" >&2; }

current_tz() {
    timedatectl show -p Timezone --value 2>/dev/null || true
}

# Any tunnel up means the public IP is not where we are.
tunnel_up() {
    local t state
    for t in vpn protonvpn tor; do
        [[ -x "$TOGGLES/toggle-$t.sh" ]] || continue
        state=$("$TOGGLES/toggle-$t.sh" get 2>/dev/null || echo off)
        [[ "$state" == "on" ]] && { echo "$t"; return 0; }
    done
    return 1
}

# A timezone name is used as a path under /usr/share/zoneinfo, so it is
# validated as one before it goes anywhere near timedatectl — never trust a
# network response to name a file.
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
        log "disabled (remove $DISABLED_FLAG to re-enable)"
        return 0
    fi

    if tunnel=$(tunnel_up); then
        log "$tunnel is up — refusing to set the timezone from a tunnelled IP"
        return 0
    fi

    cur=$(current_tz)
    if ! want=$(detect_tz); then
        log "could not determine a timezone (offline?), leaving $cur alone"
        return 0
    fi

    if ! valid_tz "$want"; then
        log "provider returned an unusable timezone '$want', ignoring"
        return 0
    fi

    if [[ "$want" == "$cur" ]]; then
        log "already $cur"
        return 0
    fi

    if [[ "$dry" == "--dry-run" ]]; then
        log "would change $cur -> $want"
        return 0
    fi

    if timedatectl set-timezone "$want"; then
        log "changed $cur -> $want"
        # The shell renders the clock from the system zone; tell the user the
        # machine's idea of "now" just moved rather than letting them find out
        # from a missed meeting.
        command -v notify-send >/dev/null &&
            notify-send -a Timezone "Timezone updated" "$cur → $want" || true
        # Running quickshell surfaces re-read the zone on their next tick;
        # nudge anything that caches it.
        command -v systemctl >/dev/null &&
            systemctl --user try-restart quickshell.service >/dev/null 2>&1 || true
    else
        log "timedatectl refused; is the polkit rule from configs/timezone-auto installed?"
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
