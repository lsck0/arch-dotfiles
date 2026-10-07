#!/usr/bin/env bash
# Shared helpers for toggle-*.sh: an on/off value store and a uniform get/label/on/off/toggle CLI

TOGGLES_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/toggles"
# sourced by every toggle run, status.sh runs them all at once: no forks here
[[ -d "$TOGGLES_STATE_DIR" ]] || mkdir -p "$TOGGLES_STATE_DIR"

toggle_get() {
    local file="$TOGGLES_STATE_DIR/$1"
    if [[ -f "$file" ]]; then echo "$(<"$file")"; else echo off; fi
}

toggle_set() {
    echo -n "$2" >"$TOGGLES_STATE_DIR/$1"
}

# tmpfs-backed variant for a toggle whose tool resets on boot (e.g. tlp): wiped with the real state, so status can't go stale
TOGGLES_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}/toggles"
[[ -d "$TOGGLES_RUNTIME_DIR" ]] || mkdir -p "$TOGGLES_RUNTIME_DIR"

toggle_get_volatile() {
    local file="$TOGGLES_RUNTIME_DIR/$1"
    if [[ -f "$file" ]]; then echo "$(<"$file")"; else echo off; fi
}

toggle_set_volatile() {
    echo -n "$2" >"$TOGGLES_RUNTIME_DIR/$1"
}

# a toggle changed state: ping quickshell's toggles ipc (status refresh without polling, keybinds and gamemode included), then notify-send; never blocking
toggle_notify() {
    timeout 2 quickshell ipc -p "$HOME/.config/quickshell" call toggles changed "${0##*/}" >/dev/null 2>&1 || true
    timeout 2 notify-send "$@" 2>/dev/null || true
}

# toggle_index_of <state> <miss> <states...>: the index of state in states, miss when absent
toggle_index_of() {
    local state=$1 miss=$2 i
    shift 2
    for ((i = 1; i <= $#; i++)); do [[ "${!i}" == "$state" ]] && { echo $((i - 1)); return; }; done
    echo "$miss"
}

# toggle_main <name> <label> <check_fn> <on_fn> <off_fn> <action> check_fn must echo "on" or "off" and take no arguments.
toggle_main() {
    local label=$2 check_fn=$3 on_fn=$4 off_fn=$5 action=${6:-toggle}
    local current
    current=$("$check_fn")
    [[ $action == toggle ]] && { [[ $current == on ]] && action=off || action=on; }

    case "$action" in
    get)
        echo "$current"
        ;;
    label)
        if [[ "$current" == on ]]; then echo "● $label (on)"; else echo "○ $label (off)"; fi
        ;;
    on)
        "$on_fn"
        toggle_notify -a Toggles "$label" "Turned on"
        ;;
    off)
        "$off_fn"
        toggle_notify -a Toggles "$label" "Turned off"
        ;;
    *)
        echo "usage: $(basename "$0") {get|label|on|off|toggle}" >&2
        exit 1
        ;;
    esac
}

# a systemd unit: is-active is the state, sudo start/stop the switch; unit is toggle_service's local
toggle_service_check() { systemctl is-active --quiet "$unit" && echo on || echo off; }
toggle_service_start() { sudo systemctl start "$unit"; }
toggle_service_stop() { sudo systemctl stop "$unit"; }

# toggle_service <name> <label> <unit> <action>
toggle_service() {
    local unit=$3
    toggle_main "$1" "$2" toggle_service_check toggle_service_start toggle_service_stop "$4"
}

# an nmcli radio (wifi, wwan); radio is toggle_radio's local
toggle_radio_check() { [[ "$(nmcli radio "$radio" 2>/dev/null)" == enabled ]] && echo on || echo off; }
toggle_radio_on() { nmcli radio "$radio" on; }
toggle_radio_off() { nmcli radio "$radio" off; }

# toggle_radio <name> <label> <wifi|wwan> <action>
toggle_radio() {
    local radio=$3
    toggle_main "$1" "$2" toggle_radio_check toggle_radio_on toggle_radio_off "$4"
}
