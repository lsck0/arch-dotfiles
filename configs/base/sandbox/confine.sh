#!/bin/sh
# Run a GUI app hardened, e.g. `confine -- discord`. sh, not nu: a nu script evaluates and requotes its --flag=value
# arguments, "$@" passes them on untouched.
set -eu

USAGE="usage: confine [--] <command...>"
SLICE=confined.slice

case ${1:-} in
    -h | --help)
        echo "$USAGE: run a GUI app hardened"
        exit 0
        ;;
    --) shift ;;
esac
if [ $# -eq 0 ]; then
    echo "$USAGE" >&2
    exit 2
fi
unit=confine-${1##*/}-$$
scope=$unit-caller.scope
# a service (scopes reject sandboxing) bound to a scope, since --wait alone survives ctrl-c. No NoNewPrivileges (it
# denies apparmor cx/px transitions) or namespace, /tmp and home limits: electron needs them
exec systemd-run --user --scope --quiet "--unit=$scope" -- \
    systemd-run --user --pipe --wait --quiet --collect --same-dir "--unit=$unit.service" "--slice=$SLICE" \
    -p ProtectKernelTunables=yes -p ProtectKernelLogs=yes -p ProtectKernelModules=yes -p ProtectControlGroups=yes \
    -p RestrictSUIDSGID=yes -p RestrictRealtime=yes -p LockPersonality=yes -p ProtectClock=yes \
    -p "BindsTo=$scope" -p "After=$scope" -- "$@"
