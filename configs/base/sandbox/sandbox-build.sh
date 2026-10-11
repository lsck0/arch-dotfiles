#!/usr/bin/env bash
# Run an untrusted build/test command confined by systemd (transient --user unit): NO network, no new privileges,
# kernel knobs protected, and the filesystem read-only except the working dir and a private /tmp. Pre-fetch deps
# first (network is off by design — that's the anti-exfil point). The fuzzing/analysis layer runs adversarial code.
#
#   sandbox-build -- cargo test          # confine to $PWD
#   sandbox-build -w ./crate -- make      # confine to ./crate
set -euo pipefail

work="$PWD"
while [[ "${1:-}" == -w ]]; do work="$(realpath "$2")"; shift 2; done
[[ "${1:-}" == -- ]] && shift
[[ $# -gt 0 ]] || { echo "usage: sandbox-build [-w writable-dir] [--] <command...>" >&2; exit 2; }

exec systemd-run --user --pty --wait --collect --quiet \
    --unit="sandbox-build-$$" \
    --working-directory="$work" \
    -p PrivateNetwork=yes \
    -p NoNewPrivileges=yes \
    -p ProtectSystem=strict \
    -p ProtectHome=read-only \
    -p ReadWritePaths="$work" \
    -p PrivateTmp=yes \
    -p ProtectKernelTunables=yes \
    -p ProtectKernelModules=yes \
    -p ProtectControlGroups=yes \
    -p RestrictSUIDSGID=yes \
    -p LockPersonality=yes \
    -- "$@"
