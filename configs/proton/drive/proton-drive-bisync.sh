#!/usr/bin/env bash
# Two-way sync ~/ProtonDrive <-> protondrive: (alternative to the mount unit).
set -euo pipefail

LOCAL="$HOME/ProtonDrive"
REMOTE="protondrive:"
mkdir -p "$LOCAL"

# First run needs --resync to establish the baseline; the marker keeps that to once.
FLAGS=(--create-empty-src-dirs --conflict-resolve newer --compare size,modtime)
if [ ! -f "$HOME/.cache/proton-drive-bisync.init" ]; then
    rclone bisync "$LOCAL" "$REMOTE" --resync "${FLAGS[@]}"
    mkdir -p "$HOME/.cache" && touch "$HOME/.cache/proton-drive-bisync.init"
else
    rclone bisync "$LOCAL" "$REMOTE" "${FLAGS[@]}"
fi
