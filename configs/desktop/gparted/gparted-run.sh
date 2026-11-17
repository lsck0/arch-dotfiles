#!/bin/sh
# pkexec target: an allow_gui action keeps only DISPLAY and XAUTHORITY, so root's gtk3 opens on xwayland at scale 1;
# this puts the xwayland scale back
export GDK_SCALE=@SCALE@
exec /usr/bin/gparted "$@"
