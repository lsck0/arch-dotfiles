#!/bin/bash
# Pomodoro timer, built the same way scripts/reminder.sh is: the phase countdown lives in a `systemd-run --user` transient timer, not in the shell.

# omarchy:summary=Pomodoro work/break timer with desktop notifications
# omarchy:args=start [work] [break] | stop | pause | resume | skip | status [-j|--json]
# omarchy:examples=pomodoro.sh start | pomodoro.sh start 50 10 | pomodoro.sh status --json | pomodoro.sh skip

set -euo pipefail

SELF=$(readlink -f "$0")
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/quickshell-pomodoro"
STATE="$STATE_DIR/state.json"
# Each armed phase gets its OWN unit name.
UNIT_PREFIX=quickshell-pomodoro
GLYPH="󰔟"

# Classic pomodoro: 25 work, 5 short break, 15 long break after every 4th work phase.
DEF_WORK=25
DEF_BREAK=5
DEF_LONG=15
LONG_EVERY=4

mkdir -p "$STATE_DIR"

now() { date +%s; }

# Two tiers on purpose.
ALERT="$(dirname "$SELF")/alert.sh"

notify() {
    "$(dirname "$SELF")/../../../scripts/notification-send.sh" -g "$GLYPH" "$1" "${2:-}" || true
}
alert()  { "$ALERT" "$1" "${2:-}" "$GLYPH" pomodoro || true; }

read_state() { [[ -s "$STATE" ]] && cat "$STATE" || echo '{}'; }

jqs() { read_state | jq -r "$1" 2>/dev/null || echo ""; }

write_state() {
    jq -cn \
        --argjson running "$1" --argjson paused "$2" --arg phase "$3" \
        --argjson endsAt "$4" --argjson cycle "$5" --argjson remaining "$6" \
        --argjson work "$7" --argjson brk "$8" --argjson long "$9" \
        '{running:$running,paused:$paused,phase:$phase,endsAt:$endsAt,cycle:$cycle,
          remaining:$remaining,work:$work,break:$brk,long:$long}' >"$STATE"
}

# Stops outstanding *timers* only, never .service units: when this runs from inside a firing phase, that phase's own service is still executing.
cancel_timer() {
    local t
    while read -r t; do
        [[ -n "$t" ]] || continue
        systemctl --user stop "$t" >/dev/null 2>&1 || true
    done < <(systemctl --user list-timers --all --no-legend --no-pager "$UNIT_PREFIX-*.timer" 2>/dev/null |
        grep -o "$UNIT_PREFIX-[0-9]*\.timer" || true)
}

arm() {
    local seconds=$1
    cancel_timer
    systemd-run --user --quiet --collect \
        --on-active="${seconds}s" --timer-property=AccuracySec=1s \
        --unit="$UNIT_PREFIX-$(now)" "$SELF" _advance
}

phase_label() {
    case "$1" in
    work) echo "Focus" ;;
    break) echo "Break" ;;
    long) echo "Long break" ;;
    *) echo "Idle" ;;
    esac
}

phase_minutes() {
    case "$1" in
    work) jqs '.work // 25' ;;
    break) jqs '.break // 5' ;;
    long) jqs '.long // 15' ;;
    esac
}

fmt() {
    local s=$1
    ((s < 0)) && s=0
    printf '%d:%02d' $((s / 60)) $((s % 60))
}

start() {
    local work=${1:-$DEF_WORK} brk=${2:-$DEF_BREAK} long=${3:-$DEF_LONG}
    [[ $work =~ ^[0-9]+$ && $work -gt 0 ]] || { echo "work minutes must be a positive integer" >&2; exit 1; }
    [[ $brk =~ ^[0-9]+$ && $brk -gt 0 ]] || { echo "break minutes must be a positive integer" >&2; exit 1; }
    write_state true false work $(( $(now) + work * 60 )) 1 0 "$work" "$brk" "$long"
    arm $((work * 60))
    notify "Focus for ${work} min" "Pomodoro 1 started"
}

stop() {
    cancel_timer
    rm -f "$STATE"
    notify "Pomodoro stopped"
}

pause() {
    [[ "$(jqs '.running')" == "true" ]] || exit 0
    [[ "$(jqs '.paused')" == "true" ]] && exit 0
    local remaining=$(( $(jqs '.endsAt') - $(now) ))
    ((remaining < 0)) && remaining=0
    cancel_timer
    write_state true true "$(jqs '.phase')" 0 "$(jqs '.cycle')" "$remaining" \
        "$(jqs '.work')" "$(jqs '.break')" "$(jqs '.long')"
    notify "Pomodoro paused" "$(fmt "$remaining") left"
}

resume() {
    [[ "$(jqs '.paused')" == "true" ]] || exit 0
    local remaining=$(jqs '.remaining')
    ((remaining <= 0)) && remaining=60
    write_state true false "$(jqs '.phase')" $(( $(now) + remaining )) "$(jqs '.cycle')" 0 \
        "$(jqs '.work')" "$(jqs '.break')" "$(jqs '.long')"
    arm "$remaining"
    notify "Pomodoro resumed" "$(fmt "$remaining") left"
}

# Advance to the next phase.
advance() {
    [[ "$(jqs '.running')" == "true" ]] || exit 0
    local phase cycle work brk long next next_min
    phase=$(jqs '.phase'); cycle=$(jqs '.cycle')
    work=$(jqs '.work'); brk=$(jqs '.break'); long=$(jqs '.long')

    if [[ "$phase" == "work" ]]; then
        if (( cycle % LONG_EVERY == 0 )); then
            next=long; next_min=$long
        else
            next=break; next_min=$brk
        fi
        alert "Focus block done" "Take a $(phase_label "$next" | tr '[:upper:]' '[:lower:]') — ${next_min} min"
    else
        next=work; next_min=$work
        cycle=$((cycle + 1))
        alert "Break over" "Focus for ${work} min — pomodoro ${cycle}"
    fi

    write_state true false "$next" $(( $(now) + next_min * 60 )) "$cycle" 0 "$work" "$brk" "$long"
    arm $((next_min * 60))
}

status_json() {
    local running paused phase endsAt cycle remaining
    running=$(jqs '.running'); [[ "$running" == "true" ]] || running=false
    if [[ "$running" != "true" ]]; then
        jq -cn --argjson work "$DEF_WORK" --argjson longEvery "$LONG_EVERY" \
            '{running:false,paused:false,phase:"idle",label:"Pomodoro",remainingSeconds:0,remaining:"",
              cycle:0,totalSeconds:0,defaultWork:$work,longEvery:$longEvery,tooltip:"Pomodoro: off"}'
        return
    fi
    paused=$(jqs '.paused'); phase=$(jqs '.phase'); cycle=$(jqs '.cycle')
    if [[ "$paused" == "true" ]]; then
        remaining=$(jqs '.remaining')
    else
        endsAt=$(jqs '.endsAt'); remaining=$((endsAt - $(now)))
    fi
    ((remaining < 0)) && remaining=0
    local total
    case "$phase" in
    work) total=$(( $(jqs '.work') * 60 )) ;;
    long) total=$(( $(jqs '.long') * 60 )) ;;
    *) total=$(( $(jqs '.break') * 60 )) ;;
    esac
    jq -cn --argjson running true --argjson paused "${paused:-false}" \
        --arg phase "$phase" --arg label "$(phase_label "$phase")" \
        --argjson remainingSeconds "$remaining" --arg remaining "$(fmt "$remaining")" \
        --argjson cycle "$cycle" --argjson totalSeconds "$total" --argjson longEvery "$LONG_EVERY" \
        --arg tooltip "$(phase_label "$phase") · $(fmt "$remaining") left · pomodoro $cycle$([[ "$paused" == "true" ]] && echo ' (paused)')" \
        '{running:$running,paused:$paused,phase:$phase,label:$label,
          remainingSeconds:$remainingSeconds,remaining:$remaining,cycle:$cycle,
          totalSeconds:$totalSeconds,longEvery:$longEvery,tooltip:$tooltip}'
}

usage() {
    echo "Usage: pomodoro.sh start [work] [break] [longbreak]"
    echo "       pomodoro.sh stop | pause | resume | skip"
    echo "       pomodoro.sh status [-j|--json]"
}

case ${1:-status} in
start) shift; start "$@" ;;
stop) stop ;;
pause) pause ;;
resume) resume ;;
toggle)
    if [[ "$(jqs '.running')" != "true" ]]; then start
    elif [[ "$(jqs '.paused')" == "true" ]]; then resume
    else pause; fi
    ;;
skip | _advance) advance ;;
status)
    case ${2:-} in
    -j | --json) status_json ;;
    "") s=$(status_json); echo "$(jq -r '.tooltip' <<<"$s")" ;;
    *) usage; exit 1 ;;
    esac
    ;;
*) usage; exit 1 ;;
esac
