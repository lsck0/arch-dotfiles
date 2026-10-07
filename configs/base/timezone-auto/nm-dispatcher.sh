#!/usr/bin/env bash
# NM dispatcher: only a network change can move the timezone, so re-check on one instead of polling; link.sh bakes in the user
case "$2" in up | connectivity-change) ;; *) exit 0 ;; esac
[ "$2" != connectivity-change ] || [ "$CONNECTIVITY_STATE" = FULL ] || exit 0
systemctl --user -M "@USER@@" start --no-block timezone-auto.service 2>/dev/null || true
