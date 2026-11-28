#!/bin/sh
# qvidcap's gl setup fails on native wayland and it exits; under xwayland it runs.
set -eu

export QT_QPA_PLATFORM=xcb
# qt on xcb sees xwayland's 96 dpi and ignores GDK_SCALE, so the session's xwayland scale is handed over at run time
export QT_SCALE_FACTOR="${QT_SCALE_FACTOR:-${GDK_SCALE:-1}}"
exec /usr/bin/qvidcap "$@"
