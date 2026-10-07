#!/usr/bin/env bash
# the machine ledger moved out of the admin's home: merge the pkg, snapshot and unit system lines of the ledger the admin
# running this (sudo) kept in ~/.local/state into $SYSTEM_STATE/ledger, so nothing it owned becomes unowned
set -euo pipefail

source "$DOTFILES/scripts/lib/system.sh"
MACHINE_LEDGER="$SYSTEM_STATE/ledger"
# a line is data: a package name, or a unit the ledger's own name check passes later
LINE_PATTERN='^(pkg [A-Za-z0-9@._+-]+|unit system [A-Za-z0-9@:_.-]+)$'

# pending until an admin's run (config.sh) reaches it with that admin's name
[[ -n "${SUDO_USER:-}" ]] || { echo "machine-ledger: no SUDO_USER, rerun through config.sh" >&2; exit 1; }
home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
old_ledger="$home/.local/state/dotfiles/ledger"
[[ -f "$old_ledger" ]] || exit 0

mkdir -p "$SYSTEM_STATE"
{
    cat "$MACHINE_LEDGER" 2>/dev/null || true
    grep -E "$LINE_PATTERN" "$old_ledger" || true
    # one snapshot line, the machine's own when install already wrote one
    grep -q '^snapshot ' "$MACHINE_LEDGER" 2>/dev/null || grep -m1 -E '^snapshot [^[:space:]]+ [^[:space:]]+ [0-9a-f]{64}$' "$old_ledger" || true
} | sort -u >"$MACHINE_LEDGER.new"
chmod 644 "$MACHINE_LEDGER.new"
mv -f "$MACHINE_LEDGER.new" "$MACHINE_LEDGER"
