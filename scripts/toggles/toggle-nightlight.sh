#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# 4000K whitepoint in the display CTM, composed with the grading preset by color-grading.py
GRADING=../../configs/desktop/color-grading/color-grading.py

check() { "$GRADING" get nightlight; }
turn_on() { "$GRADING" set nightlight on; }
turn_off() { "$GRADING" set nightlight off; }

toggle_main nightlight "Night light" check turn_on turn_off "${1:-toggle}"
