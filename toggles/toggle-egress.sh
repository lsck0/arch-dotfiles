#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

EGRESS="$HOME/projects/arch-dotfiles/scripts/egress.sh"

check()    { "$EGRESS" status; }
turn_on()  { "$EGRESS" up; }
turn_off() { "$EGRESS" down; }

toggle_main egress "Test Egress" check turn_on turn_off "${1:-toggle}"
