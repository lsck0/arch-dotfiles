#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# backed by quickshell notifications Service.qml; dnd still writes silenced notifications to history
qs_ipc() { quickshell ipc -p "$HOME/.config/quickshell" call notifications "$@"; }
check() { qs_ipc isDnd; }
turn_on() { qs_ipc setDnd true >/dev/null; }
turn_off() { qs_ipc setDnd false >/dev/null; }

toggle_main dnd "Do Not Disturb" check turn_on turn_off "${1:-toggle}"
