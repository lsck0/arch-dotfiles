#!/usr/bin/env bash
# NM dispatcher: only a network change can move the timezone, so re-check on one instead of polling; every logged-in
# user's timezone-auto.service, a user without the unit (or outside wheel, polkit) changes nothing
case "$2" in up | connectivity-change) ;; *) exit 0 ;; esac
[ "$2" != connectivity-change ] || [ "$CONNECTIVITY_STATE" = FULL ] || exit 0
for user in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $2}'); do
    systemctl --user -M "${user}@" start --no-block timezone-auto.service 2>/dev/null || true
done
