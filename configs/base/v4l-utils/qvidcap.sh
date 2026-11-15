#!/bin/sh
# qvidcap's gl setup fails on native wayland and it exits; under xwayland it runs. sh, not nu: a nu script evaluates
# and requotes its --flag=value arguments, "$@" passes them on untouched.
set -eu

export QT_QPA_PLATFORM=xcb
exec /usr/bin/qvidcap "$@"
