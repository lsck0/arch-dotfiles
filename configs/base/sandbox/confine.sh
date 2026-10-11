#!/usr/bin/env bash
# Run a GUI app in a systemd --user scope with conservative hardening, as defense-in-depth alongside AppArmor (aa).
# Deliberately does NOT set RestrictNamespaces/PrivateTmp/ProtectHome: Chromium/Electron need user namespaces for
# their own sandbox and a shared /tmp and $HOME/.config to work. Groups confined apps under confined.slice.
#
#   confine -- discord
#   confine -- signal-desktop
set -euo pipefail

[[ "${1:-}" == -- ]] && shift
[[ $# -gt 0 ]] || { echo "usage: confine [--] <command...>" >&2; exit 2; }

exec systemd-run --user --scope --quiet --collect \
    --unit="confine-$(basename "$1")-$$" \
    --slice=confined.slice \
    -p NoNewPrivileges=yes \
    -p ProtectKernelTunables=yes \
    -p ProtectKernelLogs=yes \
    -p ProtectKernelModules=yes \
    -p ProtectControlGroups=yes \
    -p RestrictSUIDSGID=yes \
    -p RestrictRealtime=yes \
    -p LockPersonality=yes \
    -p ProtectClock=yes \
    -- "$@"
