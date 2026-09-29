#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

ANONYMOUS_NETWORK_PERSONA="$HOME/projects/arch-dotfiles/scripts/anonymous-network-persona.sh"

check()    { "$ANONYMOUS_NETWORK_PERSONA" status; }
turn_on()  { "$ANONYMOUS_NETWORK_PERSONA" up; }
turn_off() { "$ANONYMOUS_NETWORK_PERSONA" down; }

toggle_main anonymous-network-persona "Anonymous Network Persona" check turn_on turn_off "${1:-toggle}"
