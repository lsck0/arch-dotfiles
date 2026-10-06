#!/usr/bin/env bash
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

ANONYMOUS_SOCKS="$DOTFILES/scripts/lib/anonymous-socks.sh"

check()    { "$ANONYMOUS_SOCKS" status; }
turn_on()  { "$ANONYMOUS_SOCKS" up; }
turn_off() { "$ANONYMOUS_SOCKS" down; }

toggle_main anonymous-socks "Anonymous SOCKS" check turn_on turn_off "${1:-toggle}"
