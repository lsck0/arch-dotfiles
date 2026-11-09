#!/bin/sh
# The system agent's session, run by hermes-system-agent.service in its tmux pane: the profile's most recent session
# (the list is newest first; --continue only picks up plain-cli sessions, this one is a tui session), else a new one.
id=$(hermes -p system sessions list 2> /dev/null | awk '$NF ~ /^local-/ { print $NF; exit }')
if [ -n "$id" ]; then
    exec hermes -p system --resume "$id"
fi
exec hermes -p system
