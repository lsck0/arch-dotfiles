# shellcheck shell=bash
# runs on the test vm's guest as root, fetched by dot test (scripts/lib/vm.nu); @KEY@ placeholders are filled in there
set -uo pipefail
host=@HOST@
step=$(basename "$0" .root)
say() { printf 'drill: %s=%s\n' "$1" "$2"; }
yesno() { if "$@" > /dev/null 2>&1; then echo yes; else echo no; fi; }
# a file served beside this step, to /tmp/<step>.<suffix>
fetch() { curl -so "/tmp/$step.$1" "http://$host/step/$step.$1"; }
# the output so far up to the host; a step that reboots reports first
report() { curl -sT "$0.log" "http://$host/drill.log"; }
