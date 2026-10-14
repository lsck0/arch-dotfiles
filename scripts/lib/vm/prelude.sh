# shellcheck shell=bash
set -uo pipefail
host=@HOST@
step=$(basename "$0" .root)
say() { printf 'drill: %s=%s\n' "$1" "$2"; }
yesno() { if "$@" > /dev/null 2>&1; then echo yes; else echo no; fi; }
fetch() { curl -so "/tmp/$step.$1" "http://$host/step/$step.$1"; }
# a step that reboots must report first
report() { curl -sT "$0.log" "http://$host/drill.log"; }
