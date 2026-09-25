#!/usr/bin/env bash
# Human taskwarrior/timewarrior overview: active, due, aging, burndown, week.

set -uo pipefail

# Always target the human db, even inside a project where direnv exported an agent TASKRC.
export TASKRC="$HOME/.taskrc"
unset TASKDATA TIMEWARRIORDB 2>/dev/null || true

if ! command -v task >/dev/null 2>&1; then
    echo "taskdash: taskwarrior not installed" >&2
    exit 1
fi

have_gum() { command -v gum >/dev/null 2>&1; }

heading() {
    if have_gum; then
        gum style --bold --foreground 6 ">> $1"
    else
        printf '\n>> %s\n' "$1"
    fi
}

# Run a taskwarrior report quietly, forcing colour through the pipe, and note when it is empty.
run_task() {
    local title=$1
    shift
    heading "$title"
    local out
    out=$(task rc.verbose=nothing rc._forcecolor=on "$@" 2>/dev/null)
    if [[ -n "$out" ]]; then printf '%s\n' "$out"; else echo "  (none)"; fi
}

render() {
    if have_gum; then
        gum style --border double --border-foreground 5 --padding "0 2" --bold --foreground 6 \
            "TASKDASH // $(date '+%Y-%m-%d %H:%M')"
    else
        echo "=== TASKDASH // $(date '+%Y-%m-%d %H:%M') ==="
    fi

    heading "ACTIVE TIMERS"
    if command -v timew >/dev/null 2>&1; then timew 2>/dev/null || true; fi
    task rc.verbose=nothing rc._forcecolor=on +ACTIVE 2>/dev/null || true

    run_task "OVERDUE"  +OVERDUE
    run_task "DUE TODAY" due:today
    run_task "UPCOMING (ready)" limit:10 ready
    run_task "AGING (oldest pending)" limit:10 aging
    run_task "PROJECTS" summary

    heading "BURNDOWN (daily)"
    task rc.verbose=nothing burndown.daily 2>/dev/null || echo "  (no data)"

    if command -v timew >/dev/null 2>&1; then
        heading "TIME THIS WEEK"
        timew summary :week 2>/dev/null || echo "  (no data)"
    fi
}

# `--page` pipes the whole dashboard through less; otherwise print straight to stdout.
if [[ "${1:-}" == "--page" || "${1:-}" == "-p" ]] && command -v less >/dev/null 2>&1; then
    render | less -R
else
    render
fi
