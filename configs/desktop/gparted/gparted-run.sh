#!/bin/sh
# pkexec target: an allow_gui action keeps only DISPLAY and XAUTHORITY, so root's gtk3 opens on xwayland at scale 1;
# this puts the xwayland scale back: the desktop entry's first argument (the session's), else the system layer's guess
case "$1" in
    [1-4])
        export GDK_SCALE="$1"
        shift
        ;;
    *) export GDK_SCALE=@SCALE@ ;;
esac
exec /usr/bin/gparted "$@"
