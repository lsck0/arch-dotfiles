#!/usr/bin/env bash
# drop the root nix-gc timer an older base/cleanup installed; each user's nix-gc user timer expires that user's generations
set -euo pipefail

UNIT_DIR=/etc/systemd/system

[[ -e "$UNIT_DIR/nix-gc.timer" || -e "$UNIT_DIR/nix-gc.service" ]] || exit 0
systemctl disable --now nix-gc.timer 2>/dev/null || true
rm -f "$UNIT_DIR/nix-gc.timer" "$UNIT_DIR/nix-gc.service"
systemctl daemon-reload
