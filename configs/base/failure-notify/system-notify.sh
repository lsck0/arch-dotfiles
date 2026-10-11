#!/usr/bin/env bash
# desktop notifications from the system journal: failed system units (user units have OnFailure=), smartd's disk
# warnings, and root's reports under the identifier dotfiles-health (lynis-audit). wheel reads the whole journal, a
# login outside it sees none of these entries and gets nothing
set -euo pipefail

# a unit failing over and over (an unreachable mount) shows at most hourly, replacing its own card
COOLDOWN_S=3600
declare -A shown=() last=()

# notify <key> <urgency> <title> <body>
notify() {
    local key=$1 now id
    local -a replace=()
    now=$(date +%s)
    ((now - ${last[$key]:-0} >= COOLDOWN_S)) || return 0
    last[$key]=$now
    [[ -z "${shown[$key]-}" ]] || replace=(-r "${shown[$key]}")
    id=$(notify-send -p -a system -u "$2" "${replace[@]}" "$3" "$4") || return 0
    shown[$key]=$id
}

# trusted fields only, journald sets _PID and _UID: pid 1's unit failures, root's smartd at crit and worse, root's reports
journalctl --no-pager -f -n 0 -o json \
    _PID=1 MESSAGE_ID=d9b373ed55a64feb8242e02dbe79a49c \
    + _UID=0 SYSLOG_IDENTIFIER=smartd PRIORITY=0 PRIORITY=1 PRIORITY=2 \
    + _UID=0 SYSLOG_IDENTIFIER=dotfiles-health |
    jq --unbuffered -r '[.SYSLOG_IDENTIFIER // "-", .UNIT // "-", .PRIORITY // "6",
        (.MESSAGE | if type == "string" then . else "" end)] | @tsv' |
    while IFS=$'\t' read -r ident unit priority message; do
        case "$ident" in
        smartd)
            notify smartd critical "Disk health" "$message"
            ;;
        dotfiles-health)
            # "<title>: <body>", err and worse is critical
            urgency=normal
            ((priority > 3)) || urgency=critical
            notify "${message%%: *}" "$urgency" "${message%%: *}" "${message#*: }"
            ;;
        *)
            # one that restarts on failure is not failed yet
            systemctl -q is-failed "$unit" || continue
            notify "$unit" critical "$unit failed" "journalctl -xeu $unit"
            ;;
        esac
    done
# the follow ending is a failure, so Restart= brings it back
echo "journalctl -f ended" >&2
exit 1
