#!/usr/bin/env bash
# popup.sh [-e] [sudo] <tool> [args...]: the tmux popup runner. -e loads the pane dir's direnv env first; a blocked or
# failing .envrc falls back to the plain env instead of the popup closing at once. A tool from a group this machine
# lacks says so instead of a silently closing popup

if [[ $1 == -e ]]; then
    shift
    command -v direnv >/dev/null 2>&1 && eval "$(direnv export bash 2>/dev/null)"
fi

tool=$1
[[ $tool == sudo ]] && tool=$2
if ! command -v "$tool" >/dev/null 2>&1; then
    read -rsn1 -p "${tool} is not installed (its package group is not on this machine), press any key"
    exit 127
fi
exec "$@"
