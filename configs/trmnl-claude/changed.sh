#!/usr/bin/env bash
# execcondition: post after claude activity, and at least every 5 h (the usage window) and after midnight so resets and "today" roll over
PUSHED="$HOME/.claude/.trmnl_last_push"

[[ -f "$PUSHED" && -z "$(find "$PUSHED" \( -mmin +300 -o ! -newermt "$(date +%F)" \))" ]] || exit 0
[[ -n "$(find "$HOME/.claude/projects" "$HOME/.claude/sessions" -newer "$PUSHED" -print -quit 2>/dev/null)" ]]
