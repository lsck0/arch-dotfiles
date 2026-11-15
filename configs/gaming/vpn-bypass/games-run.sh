#!/bin/sh
# pkexec target: runs the caller's command as the caller with group vpn-bypass, whose sockets leave past the vpn. It
# grants only that group; polkit asks for the key on every call, under its own action (dev.lsck0.vpn-bypass.policy),
# so no rule for another pkexec program covers it. pkexec cleared the environment, so the caller restores its own
# (steam-launch stashes it in its runtime dir).
set -eu
uid=${PKEXEC_UID:?games-run: run it through pkexec}
exec setpriv --reuid="$uid" --regid=vpn-bypass --init-groups -- "$@"
