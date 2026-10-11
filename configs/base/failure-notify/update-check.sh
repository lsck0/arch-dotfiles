#!/usr/bin/env bash
# a low-noise note when the package set this machine could upgrade to changes (a new lsck0 snapshot): how many
# updates, and which installed packages have an arch security advisory with a fix. silent while nothing changed
set -euo pipefail

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/update-check"
mkdir -p "$STATE"

# a private copy of the sync dbs, pacman's own stay as they are; 2 is "no updates", anything else (offline) waits a day
rc=0
updates=$(checkupdates --nocolor) || rc=$?
((rc == 0 || rc == 2)) || { echo "update-check: checkupdates failed ($rc), trying again tomorrow" >&2; exit 0; }
advisories=""
if command -v arch-audit >/dev/null 2>&1; then
    advisories=$(arch-audit --upgradable --quiet) || { echo "update-check: arch-audit failed" >&2; advisories=""; }
fi

digest=$(printf '%s\n--\n%s\n' "$updates" "$advisories" | sha256sum | cut -d' ' -f1)
[[ "$digest" != "$(cat "$STATE/last" 2>/dev/null)" ]] || exit 0
if [[ -n "$updates" ]]; then
    body="$(grep -c . <<<"$updates") packages, scripts/system-update.sh installs them"
    urgency=low
    if [[ -n "$advisories" ]]; then
        body+=$'\n'"security fixes for: $(paste -sd' ' <<<"$advisories")"
        urgency=normal
    fi
    # not shown (no notification daemon yet): not recorded, tomorrow's run tries again
    notify-send -a updates -u "$urgency" "Updates available" "$body" || exit 0
fi
echo "$digest" >"$STATE/last"
