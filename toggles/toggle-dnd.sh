#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# Backed by configs/quickshell/plugins/notifications/Service.qml (replaced
# mako as the active notification daemon — see TODO.md). DND there still
# writes silenced notifications straight to history (see Service.qml's
# writeSilenced), so nothing is lost, only silenced, same guarantee mako's
# `[mode=dnd]` block gave.
qs_ipc() { quickshell ipc -p "$HOME/.config/quickshell" call notifications "$@"; }
check() { qs_ipc isDnd; }
turn_on() { qs_ipc setDnd true >/dev/null; }
turn_off() { qs_ipc setDnd false >/dev/null; }

toggle_main dnd "Do Not Disturb" check turn_on turn_off "${1:-toggle}"
