#!/usr/bin/env bash
set -euo pipefail

glyph=
[[ ${1:-} == -g ]] && { glyph=$2; shift 2; }
exec notify-send -a quickshell-action -u low ${glyph:+-h "string:omarchy-glyph:$glyph"} "$1" "${2:-}"
