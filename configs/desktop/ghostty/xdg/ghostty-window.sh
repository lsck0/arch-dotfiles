#!/bin/sh
# a hung ghostty still answers d-bus pings while actions time out (25s), so kitty takes over. sh, not nu: a nu script
# evaluates and requotes its --flag=value arguments, "$@" passes them on untouched.
set -eu

if timeout 3 gdbus call --session --timeout 2 --dest com.mitchellh.ghostty --object-path /com/mitchellh/ghostty \
    --method org.gtk.Actions.List > /dev/null 2>&1; then
    exec /usr/bin/ghostty +new-window "$@"
fi

# ghostty's options in kitty's spelling, up to -e; the command after it as it is
left=$#
command=false
while [ "$left" -gt 0 ]; do
    arg=$1
    shift
    left=$((left - 1))
    if $command; then
        set -- "$@" "$arg"
        continue
    fi
    case $arg in
        -e) command=true ;;
        --title=*) set -- "$@" --title "${arg#--title=}" ;;
        --working-directory=*) set -- "$@" --directory "${arg#--working-directory=}" ;;
        *) set -- "$@" "$arg" ;;
    esac
done
exec kitty "$@"
