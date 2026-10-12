#!/usr/bin/env bash
# popup.sh [-e] [sudo] <tool> [args...]: tmux popup runner; -e loads the pane dir's direnv env (a failing .envrc is ignored), a tool a machine lacks reports instead of closing silently

if [[ $1 == -e ]]; then
    shift
    eval "$(direnv export bash 2>/dev/null)"
fi

tool=$1
[[ $tool == sudo ]] && tool=$2
if ! command -v "$tool" >/dev/null 2>&1; then
    read -rsn1 -p "${tool} is not installed (its package group is not on this machine), press any key"
    exit 127
fi
exec "$@"
