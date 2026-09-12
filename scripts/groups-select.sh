#!/usr/bin/env bash
# Interactive package-group selector. install.sh calls this automatically
# on first run if no selection file exists yet; rerun any time afterward to
# change the enabled set for a later `groups-apply.sh install|remove <group>`
# pass (see that script — this one only writes the selection, it never
# installs or removes anything itself).
#
# Asks which groups to DISABLE rather than which to enable, so "select
# nothing, press enter" is exactly the "all groups enabled by default"
# behavior the spec calls for, with no separate preselection logic needed.
set -euo pipefail

PKG_GROUPS=(base desktop programming security creating socials gaming misc)
STATE_DIR="$HOME/projects/arch-dotfiles"
STATE_FILE="$STATE_DIR/groups.conf"
mkdir -p "$STATE_DIR"

# Non-interactive (no tty, e.g. piped into a CI-style install) or fzf
# missing: default to all groups enabled per spec, don't hang waiting on
# input that can't come.
if [[ ! -t 0 ]] || ! command -v fzf >/dev/null 2>&1; then
    printf '%s\n' "${PKG_GROUPS[@]}" > "$STATE_FILE"
    echo "Non-interactive: all groups enabled by default ($STATE_FILE)." >&2
    exit 0
fi

disabled=$(printf '%s\n' "${PKG_GROUPS[@]}" | fzf --multi \
    --prompt="groups to DISABLE (tab to toggle, enter to confirm, select none to keep all enabled) > " \
    --header="This only writes $STATE_FILE. Nothing is installed or removed here — see groups-apply.sh for that.")

if [[ -z "$disabled" ]]; then
    printf '%s\n' "${PKG_GROUPS[@]}" > "$STATE_FILE"
else
    comm -23 <(printf '%s\n' "${PKG_GROUPS[@]}" | sort) <(printf '%s\n' "$disabled" | sort) > "$STATE_FILE"
fi

echo "Enabled groups written to $STATE_FILE:" >&2
cat "$STATE_FILE" >&2
