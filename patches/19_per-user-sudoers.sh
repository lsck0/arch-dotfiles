#!/usr/bin/env bash
# drop the per-user sudoers drop-ins (00_user, 00_<user>, 10-<user>-nopasswd) now that the static 10-wheel grants every admin;
# a file only goes once 10-wheel parses and every user it names is in wheel, so no admin loses sudo; until then it stays pending
set -euo pipefail

SUDOERS_DIR=/etc/sudoers.d
WHEEL_DROPIN=$SUDOERS_DIR/10-wheel
# what base/sudo used to write; a file with any other rule is not ours and stays
OUR_RULE='^[a-z_][a-z0-9_.-]*[[:space:]]+ALL=\(ALL(:ALL)?\)[[:space:]]+(NOPASSWD:[[:space:]]*)?ALL$'

if [[ ! -f "$WHEEL_DROPIN" ]] || ! visudo -cqf "$WHEEL_DROPIN"; then
    echo "per-user-sudoers: $WHEEL_DROPIN missing or invalid, keeping every per-user grant" >&2
    exit 1
fi
status=0
for file in "$SUDOERS_DIR"/00_* "$SUDOERS_DIR"/10-*-nopasswd; do
    [[ -f "$file" ]] || continue
    rules=$(grep -vE '^[[:space:]]*(#|Defaults|$)' "$file" || true)
    grep -qvE "$OUR_RULE" <<<"$rules" && continue
    keep=0
    for user in $(awk '{ print $1 }' <<<"$rules"); do
        id -nG "$user" 2>/dev/null | grep -qw wheel || keep=1
    done
    if ((keep)); then
        echo "per-user-sudoers: keeping $file, it grants a user outside wheel" >&2
        status=1
        continue
    fi
    rm -f "$file"
done
exit "$status"
