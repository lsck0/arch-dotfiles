#!/usr/bin/env bash
# launch every steam game under gamemode, with the mangohud overlay (hidden until toggled)
# and obs capture ready; $LIB lets ld.so pick the 64 or 32 bit gamemode auto-loader per game
export MANGOHUD=1
export OBS_VKCAPTURE=1
export LD_PRELOAD="/usr/\$LIB/libgamemodeauto.so.0${LD_PRELOAD:+:${LD_PRELOAD}}"
exec /usr/bin/steam "$@"
